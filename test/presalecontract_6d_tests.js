const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const stableDecimalAdjustment = BigInt(10 ** 6);
const precision = 10_000n;

async function deploy() {
  const [manager, spender, owner] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("PresaleContract");
  const block = await ethers.provider.getBlock('latest');
  const timeNow = block.timestamp;
  
  const dummyFactory = await ethers.getContractFactory("DummyERC20");
  const dummyStableFactory = await ethers.getContractFactory("DummyStable");
  const dummy1XMM = await dummyFactory.deploy();
  const dummyToken = await dummyStableFactory.deploy();

  // We transfer some dummy tokens to the spender
  // This is to simulate the user having tokens to pay with
  await dummyToken.transfer(spender, 20_000n * stableDecimalAdjustment);

  const dummy1XMMAddress = await dummy1XMM.getAddress();
  // 5 US cents equals to 500 with 4-digits precision
  const pscontract = await contractFactory.deploy(owner, dummy1XMMAddress, timeNow, timeNow + 4800000, 500);

  const pscontractAddress = await pscontract.getAddress();
  await dummy1XMM.transfer(pscontractAddress, 1_000_000n * decimalAdjustment);

  return [manager, spender, pscontract, dummy1XMM, dummyToken, owner];
}

describe('Test presale contract functions', function () {
    it('Can manage tokens with 6 decimals', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken, owner] = await deploy();

      // We authorized dummy token
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), await dummyToken.decimals(), 1n * precision); // 1 dummy token = 20 1XMM
      const price = await pscontract.getPrice(await dummyToken.getAddress());

      expect(price).to.equal(20n * precision);

      // We add spender as authorized user
      await pscontract.addAuthorizedUser(spender);
      await dummyToken.connect(spender).approve(await pscontract.getAddress(), 1_000n * stableDecimalAdjustment);

      // Spender executes the exchange
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 1_000n * stableDecimalAdjustment)).to.be.emit(pscontract, "TradeExecuted");

      expect(await dummy1XMM.balanceOf(spender)).to.equal(20_000n * decimalAdjustment);
      expect(await dummyToken.balanceOf(owner)).to.equal(1_000n * stableDecimalAdjustment);
    });
});