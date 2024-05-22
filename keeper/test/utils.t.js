const { ethers } = require('ethers');
const { expect } = require('chai');
const sinon = require('sinon');
const {
    isStrategyOverexposed,
    isStrategyAtRisk,
    checkAlertChannelsExist,
} = require('../src/actions/checks');

describe('utils', () => {
    let strategyStub;

    beforeEach(() => {
        strategyStub = {
            currentCollateralRatio: sinon.stub(),
            getCollateralRatioTargets: sinon.stub(),
            debtUSD: sinon.stub(),
            collateralUSD: sinon.stub(),
        };
    });

    afterEach(() => {
        sinon.restore();
    });

    describe('isStrategyOverexposed', () => {
        it('returns false, and, currentCollateralRatio and minForRebalance values when currentCollateralRatio value is above minForRebalance value', async () => {
            strategyStub.currentCollateralRatio.resolves(100);
            strategyStub.getCollateralRatioTargets.resolves([100, 90, 110, 99, 101]);

            const result = await isStrategyOverexposed(strategyStub);

            expect(result.isOverExposed).to.eq(false);
            expect(result.current).to.deep.eq(ethers.BigNumber.from(String(100).toString()));
            expect(result.min).to.deep.eq(ethers.BigNumber.from(String(90).toString()));
        });

        it('returns true, and, currentCollateralRatio and minForRebalance values when currentCollateralRatio value is beneath minForRebalance value', async () => {
            strategyStub.currentCollateralRatio.resolves(85);
            strategyStub.getCollateralRatioTargets.resolves([100, 90, 110, 99, 101]);

            const result = await isStrategyOverexposed(strategyStub);

            expect(result.isOverExposed).to.eq(true);
            expect(result.current).to.deep.eq(ethers.BigNumber.from(String(85).toString()));
            expect(result.min).to.deep.eq(ethers.BigNumber.from(String(90).toString()));
        });

        it('should handle errors', async () => {
            strategyStub.currentCollateralRatio.rejects(new Error('error thrown'));
            const consoleErrorStub = sinon.stub(console, 'error');

            await isStrategyOverexposed(strategyStub);

            sinon.assert.calledOnce(consoleErrorStub);
            expect(consoleErrorStub.firstCall.args[0]).to.include(
                'An error has occured during collateral ratio check: '
            );

            console.error.restore();
        });

        it('should log an error and rethrow it when isStrategyOverexposed fails', async function () {
            const consoleErrorSpy = sinon.spy(console, 'error');
            const error = new Error('Test error');
            strategyStub.currentCollateralRatio.resolves(ethers.BigNumber.from('1000'));
            strategyStub.getCollateralRatioTargets.rejects(error);

            try {
                await isStrategyOverexposed(strategyStub);
            } catch (err) {
                expect(err).to.equal(error);
            }
            
            const actualCall = consoleErrorSpy.getCall(0);
            const expectedMessage = 'An error has occurred during collateral ratio check: ';

            expect(actualCall.args[0]).to.include(expectedMessage);
            expect(actualCall.args[1]).to.equal(error);

            consoleErrorSpy.restore();
        });
    });

    describe('isStrategyAtRisk', () => {
        const healthFactorThreshold = 10 ** 8;

        it('returns false and healthFactor value when healthFactor is above healthFactorThreshold', async () => {
            strategyStub.debt.resolves(10 ** 8);
            strategyStub.collateral.resolves(healthFactorThreshold + 1);

            const result = await isStrategyAtRisk(strategyStub, healthFactorThreshold);

            expect(result.isAtRisk).to.eq(false);
            expect(result.healthFactor).to.eq(healthFactorThreshold + 1);
        });

        it('returns true and healthFactor value when healthFactor is below healthFactorThreshold', async () => {
            strategyStub.debt.resolves(10 ** 8);
            strategyStub.collateral.resolves(healthFactorThreshold - 1);

            const result = await isStrategyAtRisk(strategyStub, healthFactorThreshold);

            expect(result.isAtRisk).to.eq(true);
            expect(result.healthFactor).to.eq(healthFactorThreshold - 1);
        });

        it('should handle errors', async () => {
            strategyStub.debt.rejects(new Error('error thrown'));
            const consoleErrorStub = sinon.stub(console, 'error');

            await isStrategyAtRisk(strategyStub, healthFactorThreshold);

            sinon.assert.calledOnce(consoleErrorStub);
            expect(consoleErrorStub.firstCall.args[0]).to.include(
                'An error has occurred during health factor check: '
            );

            console.error.restore();
        });
    });

    describe('checkAlertChannelsExist', () => {
        let clientStub;

        beforeEach(() => {
            clientStub = {
                monitor: {
                    listNotificationChannels: sinon.stub(),
                },
            };
        });

        it('handles errors when array returned is empty', async () => {
            clientStub.monitor.listNotificationChannels.resolves([]);

            const consoleErrorStub = sinon.stub(console, 'error');

            await checkAlertChannelsExist(clientStub);

            sinon.assert.calledOnce(consoleErrorStub);
            sinon.assert.calledWith(consoleErrorStub, 'No alert notification channels exist.');

            console.error.restore();
        });

        it('handles errors when array returned is non-empty but no names resolve to `seamless-alerts`', async () => {
            clientStub.monitor.listNotificationChannels.resolves([
                {
                    name: 'not-seamless-alerts',
                },
            ]);

            const consoleErrorStub = sinon.stub(console, 'error');

            await checkAlertChannelsExist(clientStub);

            sinon.assert.calledOnce(consoleErrorStub);
            sinon.assert.calledWith(consoleErrorStub, 'No alert notification channels exist.');

            console.error.restore();
        });

        it('throws no error when array returns is non-empty and has an item with the name property equal to `seamless-alerts`', async () => {
            clientStub.monitor.listNotificationChannels.resolves([
                {
                    name: 'seamless-alerts',
                },
            ]);

            const consoleErrorStub = sinon.stub(console, 'error');

            await checkAlertChannelsExist(clientStub);

            sinon.assert.notCalled(consoleErrorStub);

            console.error.restore();
        });
    });
});
