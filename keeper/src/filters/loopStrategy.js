const { ethers } = require('ethers');
const { KeyValueStoreClient } = require('defender-kvstore-client');
const {
    isStrategyAtRisk,
    isStrategyOverexposed,
    hasEPSDecreased,
    isOracleOut,
} = require('../actions/checks');
const { updateEPS, equityPerShare } = require('../actions/utils');

const depositSig = 'Deposit(address,address,uint256,uint256)';
const withdrawSig = 'Withdraw(address,address,address,uint256,uint256)';
const priceUpdateSig = 'AnswerUpdated(int256,uint256,uint256)';
const poolLiquidationSig = 'LiquidationCall(address,address,address,uint256,uint256,address,bool)';
const poolBorrowSig = 'Borrow(address,address,address,uint256,uint8,uint256,uint16)';
const poolRepaySig = 'Repay(address,address,address,uint256,bool)';
const poolWithdrawSig = 'Withdraw(address,address,address,uint256)';
const poolSupplySig = 'Supply(address,address,address,uint256,uint16)';

// 0x258730e23cF2f25887Cb962d32Bd10b878ea8a4e: 3x wstETH/WETH
// 0x2FB1bEa0a63F77eFa77619B903B2830b52eE78f4: 1.5x WETH/USDC

// 0xa669E5272E60f78299F4824495cE01a3923f4380: wstETH-ETH
// 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70: ETH-USD
// 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B: USDC-USD
const oracleToStrategies = {
    '0xa669E5272E60f78299F4824495cE01a3923f4380': ['0x258730e23cF2f25887Cb962d32Bd10b878ea8a4e'],
    '0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70': [
        '0x258730e23cF2f25887Cb962d32Bd10b878ea8a4e',
        '0x2FB1bEa0a63F77eFa77619B903B2830b52eE78f4',
    ],
    '0x7e860098F58bBFC8648a4311b374B1D669a2bc6B': ['0x2FB1bEa0a63F77eFa77619B903B2830b52eE78f4'],
};

const strategyInterestThreshold = {
    '0x258730e23cF2f25887Cb962d32Bd10b878ea8a4e': ethers.BigNumber.from(
        ethers.utils.parseUnits('3.0', 27)
    ), // 3% in RAY
    '0x2FB1bEa0a63F77eFa77619B903B2830b52eE78f4': ethers.BigNumber.from(
        ethers.utils.parseUnits('5.0', 27)
    ), // 5% in RAY
};

// 0x4200000000000000000000000000000000000006: WETH
// 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913: USDC
const debtTokenToStrategies = {
    '0x4200000000000000000000000000000000000006': ['0x258730e23cF2f25887Cb962d32Bd10b878ea8a4e'],
    '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913': ['0x2FB1bEa0a63F77eFa77619B903B2830b52eE78f4'],
};

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

const oracleABI = [
    'function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80)',
    'function latestAnswer() external view returns (uint256)',
];

const poolABI = [
    'function getReserveData(address) external view returns (tuple(uint256,uint128,uint128,uint128,uint128,uint128,uint40,uint16,address,address,address,address,uint128,uint128,uint128))',
];

const RPC_URL = 'some_rpc_url';

const healthFactorThreshold = ethers.BigNumber.from(ethers.utils.parseUnits('1.1', 8)); //value used for testing

function createMatch(hash, type, metadata) {
    return {
        hash,
        metadata: {
            type,
            ...metadata,
        },
    };
}

async function handleWithdrawOrDeposit(
    reasonType,
    reason,
    evtHash,
    matches,
    provider,
    store,
    strategyABI
) {
    const strategy = new ethers.Contract(
        ethers.utils.getAddress(reason.address),
        strategyABI,
        provider
    );
    const [riskState, exposureState, EPSState] = await Promise.all([
        isStrategyAtRisk(strategy, healthFactorThreshold),
        isStrategyOverexposed(strategy),
        hasEPSDecreased(store, strategy),
    ]);

    console.log('riskState: ', riskState);
    console.log('exposureState: ', exposureState);
    console.log('EPSState: ', EPSState);

    if (riskState.isAtRisk) {
        matches.push(createMatch(evtHash, reasonType, { riskState }));
    }
    if (exposureState.isOverExposed) {
        matches.push(createMatch(evtHash, reasonType, { exposureState }));
    }
    if (EPSState.hasEPSDecreased) {
        matches.push(createMatch(evtHash, reasonType, { EPSState }));
    }
}

async function handlePriceUpdate(reason, evtHash, matches, provider, store, strategyABI) {
    const oracleAddress = ethers.utils.getAddress(reason.address);
    const oracle = new ethers.Contract(oracleAddress, oracleABI, provider);
    const latestAnswer = await oracle.latestAnswer();
    const strategiesToRebalance = [];

    for (let affectedStrategy of oracleToStrategies[oracleAddress] || []) {
        const strategy = new ethers.Contract(affectedStrategy, strategyABI, provider);

        // update equityPerShare because price fluctuations may alter it organically
        await updateEPS(store, affectedStrategy, await equityPerShare(strategy));

        if (await strategy.rebalanceNeeded()) {
            strategiesToRebalance.push(affectedStrategy);
        }
    }

    const [oracleState, isSequencerOut] = await Promise.all([
        isOracleOut(store, oracle),
        latestAnswer === 1,
    ]);

    if (strategiesToRebalance.length > 0 || oracleState.isOut || isSequencerOut) {
        matches.push(
            createMatch(evtHash, 'priceUpdate', {
                strategiesToRebalance,
                oracleState,
                isSequencerOut,
            })
        );
    }
}

async function handlePoolAction(reason, evtHash, matches, provider, poolABI) {
    const reserveAddress = ethers.utils.getAddress(reason.args[0]);
    console.log('reserveAddress: ', reserveAddress);

    if (reserveAddress in debtTokenToStrategies) {
        const pool = new ethers.Contract(
            ethers.utils.getAddress(reason.address),
            poolABI,
            provider
        );
        const reserveData = await pool.getReserveData(reserveAddress);
        const variableBorrowRate = reserveData[3];

        const affectedStrategies = debtTokenToStrategies[reserveAddress].filter((strategy) =>
            strategyInterestThreshold[strategy].lt(variableBorrowRate)
        );

        console.log('variableBorrowRate: ', variableBorrowRate);
        console.log('affectedStrategies: ', affectedStrategies);

        if (affectedStrategies.length > 0) {
            matches.push(
                createMatch(evtHash, 'borrowRate', {
                    reserve: reserveAddress,
                    currBorrowRate: variableBorrowRate,
                    affectedStrategies,
                })
            );
        }
    }
}

exports.handler = async function (payload) {
    const conditionRequest = payload.request.body;
    const matches = [];
    const events = conditionRequest.events;
    const provider = new ethers.providers.JsonRpcProvider(RPC_URL);
    const store = new KeyValueStoreClient(payload);

    for (let evt of events) {
        for (let reason of evt.matchReasons) {
            let reasonSig = reason.signature;
            console.log('current match reason signature: ', reasonSig);

            try {
                if ([withdrawSig, depositSig].includes(reasonSig)) {
                    const reasonType = reasonSig === withdrawSig ? 'withdraw' : 'deposit';

                    await handleWithdrawOrDeposit(
                        reasonType,
                        reason,
                        evt.hash,
                        matches,
                        provider,
                        store,
                        strategyABI
                    );
                }

                console.log('matches: ', matches);
            } catch (err) {
                console.error('There was an error during withdraw or deposit check flow.');
                throw err;
            }

            try {
                if (reasonSig == priceUpdateSig) {
                    await handlePriceUpdate(
                        reason,
                        evt.hash,
                        matches,
                        provider,
                        store,
                        strategyABI
                    );
                }

                console.log('matches: ', matches);
            } catch (err) {
                console.log('There was an error during priceUpdate check flow.');
                throw err;
            }

            try {
                if (
                    [
                        poolBorrowSig,
                        poolRepaySig,
                        poolWithdrawSig,
                        poolSupplySig,
                        poolLiquidationSig,
                    ].includes(reasonSig)
                ) {
                    await handlePoolAction(reason, evt.hash, matches, provider, poolABI);
                }
            } catch (err) {
                console.log('There was an error during pool action check flow.');
                throw err;
            }
        }
    }

    return { matches };
};
