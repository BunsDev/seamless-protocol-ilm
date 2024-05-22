const { ethers } = require('ethers');
const { Defender } = require('@openzeppelin/defender-sdk');
const { KeyValueStoreClient } = require('defender-kvstore-client');
const { equityPerShare, updateEPS } = require('./utils');
const {
    sendHealthFactorAlert,
    sendExposureAlert,
    sendEPSAlert,
    sendOracleOutageAlert,
    sendSequencerOutageAlert,
    sendBorrowRateAlert,
} = require('./alerts');

const strategyABI = [
    'function rebalanceNeeded() external view returns (bool)',
    'function rebalance() external returns (uint256)',
    'function debtUSD() external view returns (uint256)',
    'function collateralUSD() external view returns (uint256)',
    'function currentCollateralRatio() external view returns (uint256)',
    'function getCollateralRatioTargets() external view returns (tuple(uint256,uint256,uint256,uint256,uint256))',
    'function equity() external view returns (uint256)',
    'function totalSupply() external view returns (uint256)',
];

const healthFactorThreshold = ethers.BigNumber.from(ethers.utils.parseUnits('1.1', 8)); //value used for testing

// execute rebalance operation if its necessary
async function performRebalance(strategy) {
    try {
        if (await strategy.rebalanceNeeded()) {
            const tx = await strategy.rebalance();
            console.log(`Called rebalance in ${tx.hash}`);
            return { tx: tx.hash };
        } else {
            console.log('Rebalance not needed.');
        }
    } catch (err) {
        console.error('An error occurred on rebalance call: ', err);
    }
}

async function handleStateAlert(state, stateType, alertFunction, alertParams, safeMessage) {
    if (state[stateType]) {
        await alertFunction(...alertParams);
        console.log(`Sent ${stateType} alert.`);
    } else {
        console.log(safeMessage);
    }
}

// Entrypoint for the action
exports.handler = async function (payload, context) {
    const client = new Defender(payload);
    const store = new KeyValueStoreClient(payload);
    const { notificationClient } = context;

    const provider = client.relaySigner.getProvider();
    const signer = client.relaySigner.getSigner(provider, {
        speed: 'fast',
    });

    const metadata = payload.request.body.metadata;

    if ('type' in metadata && ['withdraw', 'deposit'].includes(metadata.type)) {
        console.log('Processing  states after withdrawal or deposit...');
        console.log('Metadata to check against: ', metadata);

        if (metadata.riskState) {
            await handleStateAlert(
                metadata.riskState,
                'isAtRisk',
                sendHealthFactorAlert,
                [notificationClient, metadata.riskState.threshold, metadata.riskState.healthFactor],
                `Health factor is deemed to be safe at: ${metadata.riskState.healthFactor}.`
            );
        }

        if (metadata.exposureState) {
            await handleStateAlert(
                metadata.exposureState,
                'isOverExposed',
                sendExposureAlert,
                [notificationClient, metadata.exposureState.current, metadata.exposureState.min],
                `Exposure is deemed to be fine at ${metadata.exposureState.current}.`
            );
        }

        if (metadata.EPSState) {
            const actionType = metadata.type == 'withdraw' ? 'withdraw' : 'deposit';

            await handleStateAlert(
                metadata.EPSState,
                'hasEPSDecreased',
                sendEPSAlert,
                [
                    notificationClient,
                    metadata.EPSState.strategyAddress,
                    metadata.EPSState.currentEPS,
                    metadata.EPSState.prevEPS,
                    actionType
                ],
                `No EPS alert was sent as previous EPS was ${metadata.EPSState.prevEPS} and current EPS is ${metadata.EPSState.currentEPS}`
            );
        }

        console.log('States finished processing - alerts may have been sent out.');
    }

    if ('type' in metadata && metadata.type == 'priceUpdate') {
        console.log('Processing potential rebalances after price update...');
        console.log('Metadata to check against: ', metadata);

        if (metadata.strategiesToRebalance.length != 0) {
            try {
                console.log('Attempting to rebalance strategies...');
                const rebalancePromises = evt.metadata.strategiesToRebalance.map(
                    async (strategyToRebalance) => {
                        const strategy = new ethers.Contract(
                            strategyToRebalance,
                            strategyABI,
                            signer
                        );

                        await performRebalance(strategy);

                        // update equityPerShare because performRebalance may affect it
                        updateEPS(store, strategy.address, equityPerShare(strategy));

                        let riskState = await isStrategyAtRisk(strategy, healthFactorThreshold);
                        let exposureState = await isStrategyOverexposed(strategy);

                        await handleStateAlert(
                            riskState,
                            'isAtRisk',
                            sendHealthFactorAlert,
                            [notificationClient, riskState.threshold, riskState.healthFactor],
                            `Health factor is deemed to be safe at: ${riskState.healthFactor}.`
                        );

                        await handleStateAlert(
                            exposureState,
                            'isOverExposed',
                            sendExposureAlert,
                            [notificationClient, exposureState.current, exposureState.min],
                            `Exposure is deemed to be fine at ${exposureState.current}.`
                        );
                    }
                );

                await Promise.all(rebalancePromises);
            } catch (err) {
                console.log('There was an error when attempting to rebalance affected strategies.');
                throw err;
            }
        } else {
            console.log('No strategies needing rebalance have been detected.');
        }

        if (metadata.oracleState) {
            await handleStateAlert(
                metadata.oracleState,
                'isOut',
                sendOracleOutageAlert,
                [
                    notificationClient,
                    metadata.oracleState.oracleAddress,
                    metadata.oracleState.secondsSinceLastUpdate,
                ],
                'Oracle outage alert has not been sent.'
            );
        }

        if (metadata.isSequencerOut) {
            await handleStateAlert(
                metadata,
                'isSequencerOut',
                sendSequencerOutageAlert,
                [notificationClient],
                'Sequencer outage alert has not been sent.'
            );
        }
    }

    if ('type' in metadata && metadata.type == 'borrowRate') {
        await sendBorrowRateAlert(
            notificationClient,
            metadata.reserve,
            metadata.currBorrowRate,
            metadata.affectedStrategies
        );
        console.log('Sent borrow rate alert.');
    }
};

// unit testing
exports.performRebalance = performRebalance;
