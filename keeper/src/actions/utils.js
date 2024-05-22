const { ethers } = require('ethers');

const SCALE = ethers.BigNumber.from(ethers.utils.parseUnits('1.0', 18));

// get current equity per share
async function equityPerShare(strategy) {
    try {
        const equityBN = ethers.BigNumber.from((await strategy.equity()).toString()).mul(SCALE);
        const sharesBN = ethers.BigNumber.from((await strategy.totalSupply()).toString());

        return equityBN.div(sharesBN);
    } catch (err) {
        console.error('An error has occured during equityPerShare calculation: ', err);
    }
}

// store new value of equity per share in OZ KV store
async function updateEPS(store, strategy, currentEPS) {
    console.log('UpdateEPS: ', strategy, currentEPS);
    await store.put(strategy, currentEPS.toString());
}

exports.equityPerShare = equityPerShare;
exports.updateEPS = updateEPS;
