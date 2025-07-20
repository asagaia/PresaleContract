const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const precision = 10_000n;

async function deploy() {
  const [manager, spender, owner] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("FaultyPresaleContract1");
  const block = await ethers.provider.getBlock('latest');
  const timeNow = block.timestamp;

  const dummyFactory = await ethers.getContractFactory("DummyERC20");
  const dummy1XMM = await dummyFactory.deploy();
  const dummyToken = await dummyFactory.deploy();

  // We transfer some dummy tokens to the spender
  // This is to simulate the user having tokens to pay with
  await dummyToken.transfer(spender, 20_000n * decimalAdjustment);

  const dummy1XMMAddress = await dummy1XMM.getAddress();
  // 5 US cents equals to 500 with 4-digits precision
  // Or, 20 1XMM equal 1 USD
  const pscontract = await contractFactory.deploy(owner, dummy1XMMAddress, timeNow, timeNow + 4800000, 500);

  const pscontractAddress = await pscontract.getAddress();
  await dummy1XMM.transfer(pscontractAddress, 1_000_000n * decimalAdjustment);

  return [manager, spender, pscontract, dummy1XMM, dummyToken, owner];
}

describe('Test faulty presale contract 1 functions', function () {
    it('Presale times are correct', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken, owner] = await deploy();
      const initialOwnerBalanceOfDummyToken = await dummyToken.balanceOf(owner);

      // We add a dummy token to the authorized tokens
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 1000n); // 1 dummy token = 2 1XMM

      await pscontract.addAuthorizedUser(spender);
      await dummyToken.connect(spender).approve(await pscontract.getAddress(), 100n * decimalAdjustment);

      const originalBalance = await dummyToken.balanceOf(spender);

      // Spender executes the exchange but it fails
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 100n * decimalAdjustment)).to.be.revertedWithCustomError(pscontract, "TransferFailed");

      expect (await dummyToken.balanceOf(spender)).to.equal(originalBalance);
    });
});