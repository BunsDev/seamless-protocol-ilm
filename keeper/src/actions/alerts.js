/// This file contains only helpers to send notifications via the OZ Defender notification client.
/// No checking logic is contained herein.

async function sendOracleOutageAlert(notificationClient, oracleAddress, secondSinceLastUpdate) {
    try {
        notificationClient.send({
            channelAlias: 'seamless-alerts',
            subject: 'ORACLE OUTAGE',
            message: `Seconds elapsed since last update for ${oracleAddress}: ${secondSinceLastUpdate}. This is more than ${24 * 60 * 60 + 60} seconds`,
        });
    } catch (err) {
        console.error('Failed to send notification', err);
        throw err;
    }
}

async function sendSequencerOutageAlert(notificationClient) {
    try {
        notificationClient.send({
            channelAlias: 'seamless-alerts',
            subject: 'SEQUENCER OUTAGE',
            message: `Latest answer of sequencer oracle is 1.`,
        });
    } catch (err) {
        console.error('Failed to send notification', err);
        throw err;
    }
}

async function sendHealthFactorAlert(notificationClient, healthFactorThreshold, healthFactor) {
    try {
        notificationClient.send({
            channelAlias: 'seamless-alerts',
            subject: 'HEALTH FACTOR THRESHOLD BREACHED',
            message: `Current strategy health factor threshold is: ${healthFactorThreshold} and healthFactor is ${healthFactor} `,
        });
    } catch (err) {
        console.error('Failed to send notification', err);
        throw err;
    }
}

async function sendEPSAlert(notificationClient, strategyAddress, currentEPS, prevEPS, actionType) {
    console.log('currEPS: ', currentEPS);
    console.log('prevEPS: ', prevEPS);
    let currentEPSNum = ethers.BigNumber.from(currentEPS).toString();
    let prevEPSNum = ethers.BigNumber.from(prevEPS.toString()).toString();
    console.log('currEPSNum: ', currentEPSNum);
    console.log('prevEPSNum: ', prevEPSNum);
    try {
        notificationClient.send({
            channelAlias: 'seamless-alerts',
            subject: `STRATEGY EQUITY PER SHARE DECREASED AFTER USER ACTION: ${String(actionType).toUpperCase()} `,
            message: `This action resulted in ${strategyAddress} EPS to become ${currentEPSNum} from ${prevEPSNum} `,
        });
    } catch (err) {
        console.error('Failed to send notification', err);
        throw err;
    }
}

async function sendExposureAlert(notificationClient, currentCR, minForRebalance) {
    try {
        notificationClient.send({
            channelAlias: 'seamless-alerts',
            subject: 'STRATEGY IS OVEREXPOSED',
            message: `Current collateral ratio is ${currentCR} and minForRebalance ratio is ${minForRebalance} `,
        });
    } catch (err) {
        console.error('Failed to send notification', err);
        throw err;
    }
}

async function sendBorrowRateAlert(notificationClient, reserve, currentRate, affectedStrategies) {
    try {
        notificationClient.send({
            channelAlias: 'seamless-alerts',
            subject: 'LENDING POOL BORROW RATE EXCEEDED THRESHOLD',
            message: `Current rate for ${reserve} is ${ethers.utils.formatEther(currentRate)}, which affectes ${affectedStrategies}.`,
        });
    } catch (err) {
        console.error('Failed to send notification', err);
        throw err;
    }
}

exports.sendOracleOutageAlert = sendOracleOutageAlert;
exports.sendSequencerOutageAlert = sendSequencerOutageAlert;
exports.sendHealthFactorAlert = sendHealthFactorAlert;
exports.sendEPSAlert = sendEPSAlert;
exports.sendExposureAlert = sendExposureAlert;
exports.sendBorrowRateAlert = sendBorrowRateAlert;
