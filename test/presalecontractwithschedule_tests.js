const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

//import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
//import { ethers } from 'hardhat';
//import { expect } from 'chai';

const decimalAdjustment = BigInt(10 ** 18);
const precision = 10_000n;

async function deploy() {
  const [manager, spender, owner] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("PresaleContractWithSchedule");
  const block = await ethers.provider.getBlock('latest');
  const timeNow = block.timestamp + 5;

  const dummyFactory = await ethers.getContractFactory("DummyERC20");
  const dummy1XMM = await dummyFactory.deploy();
  const dummyToken = await dummyFactory.deploy();

  // We transfer some dummy tokens to the spender
  // This is to simulate the user having tokens to pay with
  await dummyToken.transfer(spender, 20_000n * decimalAdjustment);

  const dummy1XMMAddress = await dummy1XMM.getAddress();
  // 5 US cents equals to 500 with 4-digits precision
  // Or, 20 1XMM equal 1 USD
  const pscontract = await contractFactory.deploy(owner, dummy1XMMAddress, timeNow, [864_000n, 1_728_000n], [500, 750]);

  const pscontractAddress = await pscontract.getAddress();
  await dummy1XMM.transfer(pscontractAddress, 1_000_000n * decimalAdjustment);

  return [manager, spender, pscontract, dummy1XMM, dummyToken, owner];
}

describe('Test presale contract functions', function () {
    it('Presale times are correct', async function () {
      const [manager, spender, pscontract] = await deploy();

      const block = await ethers.provider.getBlock('latest');
      const timeNow = BigInt(block.timestamp);

      expect(await pscontract.presaleStartTime() - timeNow).to.be.greaterThanOrEqual(0n);
      expect(await pscontract.isActive()).to.be.true;
      expect(await pscontract.presaleEndTime()).to.equal(timeNow + 864_000n + 1_728_000n);
    });

    it('Prices are correct', async function () {
      const [manager, spender, pscontract] = await deploy();

      const block = await ethers.provider.getBlock('latest');
      const timeNow = BigInt(block.timestamp);

      await pscontract.setPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 7_500n * precision);

      expect(await pscontract.getPrice("0xdAC17F958D2ee523a2206206994597C13D831ec7")).to.equal(20n * precision);
      expect(await pscontract.getPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")).to.equal(150_000n * precision);

      await time.increase(864_000);
      expect(await pscontract.getPrice("0xdAC17F958D2ee523a2206206994597C13D831ec7")).to.equal(10_000n * precision / 750n);
      // 1XMM token has increased by 50% => user should receive 2/3 of the tokens
      expect(await pscontract.getPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")).to.equal(100_000n * precision);
    });

    it('Schedule does not impact end date', async function () {
      const [manager, spender, pscontract] = await deploy();

      const block = await ethers.provider.getBlock('latest');
      const timeNow = BigInt(block.timestamp);

      await time.increase(864_000 + 1_728_000);
      expect(await pscontract.isActive()).to.be.false;
      await expect(pscontract.setPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 7_500n * precision)).to.be.revertedWithCustomError(pscontract, 'EndOfPresaleError');
      await expect(pscontract.connect(spender).exchangeToken("0xdAC17F958D2ee523a2206206994597C13D831ec7", 100 * 10 ** 6)).to.be.revertedWith('E100'); // End of presale
    });

    it('Prices are properly adjusted', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken] = await deploy();

      const block = await ethers.provider.getBlock('latest');
      const timeNow = BigInt(block.timestamp);

      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 750n * precision);
      await pscontract.addAuthorizedUser(spender);

      dummyToken.connect(spender).approve(await pscontract.getAddress(), 10n * decimalAdjustment);
      await pscontract.connect(spender).exchangeToken(await dummyToken.getAddress(), 10n * decimalAdjustment);
      expect(await dummy1XMM.balanceOf(spender)).to.equal(150_000n * decimalAdjustment); // 7,500 USD worth of tokens at 5 cents each

      await time.increase(864_000);
      dummyToken.connect(spender).approve(await pscontract.getAddress(), 10n * decimalAdjustment);
      await pscontract.connect(spender).exchangeToken(await dummyToken.getAddress(), 10n * decimalAdjustment);
      expect(await dummy1XMM.balanceOf(spender)).to.equal(250_000n * decimalAdjustment); // +7,500 USD worth of tokens at 7.5 cents each
    });
});