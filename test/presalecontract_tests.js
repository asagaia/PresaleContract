const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { expect } = require('chai');

const decimalAdjustment = BigInt(10 ** 18);
const precision = 10_000n;

async function deploy() {
  const [manager, spender, owner] = await ethers.getSigners();
  const contractFactory = await ethers.getContractFactory("PresaleContract");
  const block = await ethers.provider.getBlock('latest');
  const timeNow = block.timestamp;

  const dummyFactory = await ethers.getContractFactory("DummyERC20");
  const dummy1XMM = await dummyFactory.deploy();
  const dummyToken = await dummyFactory.deploy();

  // We transfer some dummy tokens to the spender
  // This is to simulate the user having tokens to pay with
  await dummyToken.transfer(spender, 20_000n * decimalAdjustment);

  const dummy1XMMAddress = await dummy1XMM.getAddress();
  const pscontract = await contractFactory.deploy(owner, dummy1XMMAddress, timeNow + 1200000, timeNow + 4800000, 500);

  const pscontractAddress = await pscontract.getAddress();
  await dummy1XMM.transfer(pscontractAddress, 1_000_000n * decimalAdjustment);

  return [manager, spender, pscontract, dummy1XMM, dummyToken, owner];
}

describe('Test presale contract functions', function () {
    it('Presale times are correct', async function () {
      const [manager, spender, pscontract] = await deploy();

      const block = await ethers.provider.getBlock('latest');
      const timeNow = block.timestamp;

      expect(await pscontract.presaleStartTime() - 1199999n).to.be.greaterThan(0n);
      expect(await pscontract.isActive()).to.be.false;
        
      await time.increase(1200000);
      expect(await pscontract.isActive()).to.be.true;
    });

    it('Shows the correct available amount', async function () {
      const [manager, spender, pscontract, dummy1XMM] = await deploy();

      const available = await pscontract.availableForSale();
      expect(available).to.equal(1_000_000n * decimalAdjustment);

      await expect(pscontract.lockAmount(spender, 10_000n * decimalAdjustment)).to.be.revertedWith("E100");

      await time.increase(1200000);
      expect(await pscontract.isActive()).to.be.true;

      expect(await pscontract.availableForSale()).to.equal(available);

      await pscontract.lockAmount(spender, 10_000n * decimalAdjustment);
      expect(await pscontract.availableForSale()).to.equal(990_000n * decimalAdjustment);
    });

    it('Can pay with token', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken, owner] = await deploy();
      const initialOwnerBalanceOfDummyToken = await dummyToken.balanceOf(owner);

      //Prechecks//
      // Presale is not active yet
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 100n * decimalAdjustment)).to.be.revertedWith("E100");
      // We increase time to make presale active
      await time.increase(1200000);

      // Dummy token is not authorized
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 100n * decimalAdjustment)).to.be.revertedWith("E1");
      // We add a dummy token to the authorized tokens
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 1000n); // 1 dummy token = 2 1XMM

      // Spender is not authorized
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 100n * decimalAdjustment)).to.be.revertedWith("No auth.");
      await pscontract.addAuthorizedUser(spender);
        
      // Presale contract does not have allowance
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 100n * decimalAdjustment)).to.be.revertedWith("Allowance err");
      await dummyToken.connect(spender).approve(await pscontract.getAddress(), 100n * decimalAdjustment);

      // Spender executes the exchange
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 100n * decimalAdjustment)).to.be.emit(pscontract, "TradeExecuted");

      // We check the results
      expect(await dummy1XMM.balanceOf(await pscontract.getAddress())).to.equal(999_800n * decimalAdjustment);
      expect(await dummy1XMM.balanceOf(await spender.getAddress())).to.equal(200n * decimalAdjustment);
      expect(await pscontract.availableForSale()).to.equal(999_800n * decimalAdjustment); 

      expect(await dummyToken.balanceOf(owner)).to.equal(initialOwnerBalanceOfDummyToken + 100n * decimalAdjustment);
    });

    it('Can pay with ETH', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken, owner] = await deploy();
      const initialOwnerBalanceOfDummyToken = await dummyToken.balanceOf(owner);

      const intialPrice = await pscontract.getPrice("0x0000000000000000000000000000000000000000");

      //Prechecks//
      // Presale is not active yet
      await expect(pscontract.connect(spender).exchangeETH({value: decimalAdjustment})).to.be.revertedWith("E100");
      // We increase time to make presale active
      await time.increase(1200000);

      // Spender is not authorized
      await expect(pscontract.connect(spender).exchangeETH({value: decimalAdjustment})).to.be.revertedWith("No auth.");
      await pscontract.addAuthorizedUser(spender);

      // Now exchange can occur
      await expect(pscontract.connect(spender).exchangeETH({value: decimalAdjustment})).to.be.emit(pscontract, "TradeExecuted");

      // We check the results
      expect(await dummy1XMM.balanceOf(spender)).to.equal(intialPrice / precision * decimalAdjustment);
      expect(await dummy1XMM.balanceOf(await pscontract.getAddress())).to.equal((1_000_000n - intialPrice / precision) * decimalAdjustment);
      expect(await ethers.provider.getBalance(pscontract)).to.equal(decimalAdjustment);
    });

    it('Owner can transfer ETH', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken, owner] = await deploy();

      await time.increase(1200000);
      await pscontract.addAuthorizedUser(spender);

      await pscontract.connect(spender).exchangeETH({value: decimalAdjustment});
      await pscontract.connect(owner).transferETHToReceivingAccount((95n * decimalAdjustment) / 100n);

      // We approximate the balance of the owner after transfer since ETH may have been used for gas
      expect(await ethers.provider.getBalance(owner)).to.be.greaterThanOrEqual((90n * decimalAdjustment) / 100n);
      expect(await ethers.provider.getBalance(pscontract)).to.be.lessThanOrEqual((5n * decimalAdjustment) / 100n);
    });

    it('Transfers only max available with Tokens', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken, owner] = await deploy();
      const initialSpenderBalanceOfDummyToken = await dummyToken.balanceOf(spender);

      // We increase time to make presale active
      await time.increase(1200000);

      // We authorized dummy token
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 50_000n * precision); // 1 dummy token = 100,000 1XMM
      console.log("Price", await pscontract.getPrice(await dummyToken.getAddress()));

      // Spender is authorized
      await pscontract.addAuthorizedUser(spender);
        
      // Spender gives allowance to smart contract for transfer of dummyToken
      await dummyToken.connect(spender).approve(await pscontract.getAddress(), 100n * decimalAdjustment);

      // We try to exchange more than available
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 100n * decimalAdjustment)).to.be.emit(pscontract, "TradeExecuted");

      // Only 10 tokens should have been exchanged
      expect(await dummyToken.balanceOf(owner)).to.equal(1n * decimalAdjustment);
      expect(await dummyToken.balanceOf(spender)).to.equal(initialSpenderBalanceOfDummyToken - 1n * decimalAdjustment);
      expect(await dummy1XMM.balanceOf(spender)).to.equal(1_000_000n * decimalAdjustment);
      expect(await pscontract.availableForSale()).to.equal(0n);
    });

    it('Can get the expected amount of tokens', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken] = await deploy();

      // We authorized dummy token
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 2_450n * precision); // 1 dummy token = 20 * 2450 =  49,000 1XMM
      let price = await pscontract.getPrice(await dummyToken.getAddress());
      let expectedAmount = await pscontract.getExpectedAmountOf1XMM(await dummyToken.getAddress(), 10n * decimalAdjustment);
      expect(expectedAmount).to.equal(10n * decimalAdjustment * price / precision);

      // We reach the available amount
      expectedAmount = await pscontract.getExpectedAmountOf1XMM(await dummyToken.getAddress(), 1000n * decimalAdjustment);
      expect(expectedAmount).to.equal(1_000_000n * decimalAdjustment);

      // We update the price of the dummy token
      await pscontract.setPrice(await dummyToken.getAddress(), 150n * precision); //1 dummy token = 20 * 150 =  3,000 1XMM
      price = await pscontract.getPrice(await dummyToken.getAddress());
      expectedAmount = await pscontract.getExpectedAmountOf1XMM(await dummyToken.getAddress(), 100n * decimalAdjustment);
      expect(expectedAmount).to.equal(100n * decimalAdjustment * price / precision);
    });

    it('Can exchange tokens while some are locked', async function () {
      
    });

    it('Can manage tokens with 6 decimals', async function () {
      throw new Error();
    });
});