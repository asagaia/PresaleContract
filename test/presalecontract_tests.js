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
  // 5 US cents equals to 500 with 4-digits precision
  // Or, 20 1XMM equal 1 USD
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
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 50_000n * precision); // 1 dummy token = 1,000,000 1XMM

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

    it('Can lock and unlock tokens', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken] = await deploy();
      const availableForSale = await pscontract.availableForSale();
      const toBeLocked = availableForSale / 50n;

      // We increase time to make presale active
      await time.increase(1200000);

      // Unlock cannot work if no amount was already locked
      await expect(pscontract.unlockAmount(spender, 1n)).to.revertedWith("E103");

      // We cannot lock more than available
      await expect(pscontract.lockAmount(spender, availableForSale + 1n)).to.revertedWith("E101");
      // Now we lock the tokens
      await pscontract.lockAmount(spender, toBeLocked);

      expect(await pscontract.availableForSale()).to.equal(availableForSale - toBeLocked);
      await expect(pscontract.unlockAmount(spender, toBeLocked + 1n)).to.revertedWith("E103");

      await pscontract.unlockAmount(spender, toBeLocked / 2n);
      expect (await pscontract.availableForSale()).to.equal(availableForSale - toBeLocked / 2n);
    });

    it('Can transfer locked tokens', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken] = await deploy();
      const availableForSale = await pscontract.availableForSale();

      // A user wants to purchase 20,000 1XMM tokens
      const toBeLocked = availableForSale / 50n;

      // We cannot transfer if presale is not active
      await expect(pscontract.transfer(spender, 1, 1_000n * BigInt(10**6), toBeLocked)).to.revertedWith("E100");

      // We increase time to make presale active
      await time.increase(1200000);

      // We lock the tokens
      await pscontract.lockAmount(spender, toBeLocked);

      // Only owner can do the transfer
      await expect(pscontract.connect(spender).transfer(spender, 1, 1_000n * BigInt(10**6), toBeLocked)).to.revertedWith("E0");

      // We cannot transfer more than what was locked
      await expect(pscontract.transfer(spender, 1, 1_000n * BigInt(10**6), toBeLocked + 1n)).to.revertedWith("E102");

      await expect(pscontract.transfer(spender, 1, 1_000n * BigInt(10**6), toBeLocked)).to.emit(pscontract, "TONTradeExecuted");
      expect(await pscontract.availableForSale()).to.equal(availableForSale - toBeLocked);
    });

    it('Can exchange tokens while some are locked', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken] = await deploy();

      const availableForSale = await pscontract.availableForSale();
      const initialBalance = await dummyToken.balanceOf(spender);
      const toBeLocked = availableForSale / 2n;

      // We increase time to make presale active
      await time.increase(1200000);

      await expect(pscontract.lockAmount(spender, availableForSale + 1n)).to.revertedWith("E101");
      await pscontract.lockAmount(spender, toBeLocked);

      const newAvailable = await pscontract.availableForSale();
      expect(newAvailable).to.equal(availableForSale - toBeLocked);

      // We authorized dummy token
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 1_000n * precision); // 1 dummy token = 20,000 1XMM

      // Spender is authorized
      await pscontract.addAuthorizedUser(spender);

      // Spender gives allowance to smart contract for transfer of dummyToken
      await dummyToken.connect(spender).approve(await pscontract.getAddress(), 26n * decimalAdjustment);

      // We try to exchange more than available
      await expect(pscontract.connect(spender).exchangeToken(dummyToken, 26n * decimalAdjustment)).to.be.emit(pscontract, "TradeExecuted");
      expect (await dummy1XMM.balanceOf(spender)).to.equal(newAvailable);
      expect (await dummyToken.balanceOf(spender)).to.equal(initialBalance - 25n * decimalAdjustment)
    });

    it('Can send back remaining 1XMM tokens to 1XMM contract', async function () {
      const [manager, spender, pscontract, dummy1XMM, dummyToken] = await deploy();

      const initialBalance = await dummy1XMM.balanceOf(dummy1XMM)

      // We increase time to make presale active
      await time.increase(1200000);

      // We authorized dummy token
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 1_000n * precision); // 1 dummy token = 20,000 1XMM

      // Spender is authorized
      await pscontract.addAuthorizedUser(spender);

      // Spender gives allowance to smart contract for transfer of dummyToken
      await dummyToken.connect(spender).approve(await pscontract.getAddress(), 25n * decimalAdjustment);

      // Spender buys 500,000 1XMM tokens
      await pscontract.connect(spender).exchangeToken(dummyToken, 25n * decimalAdjustment);

      // 500,000 1XMM tokens are transferred back to the 1XMM contract
      await pscontract.transferRemainingTokens();

      expect(await dummy1XMM.balanceOf(dummy1XMM)).to.equal(initialBalance + 500_000n * decimalAdjustment);
    });

    it ('Ends presale if there is no more 1XMM tokens', async function() {
      const [manager, spender, pscontract, dummy1XMM, dummyToken] = await deploy();

      // We increase time to make presale active
      await time.increase(1200000);

      // We authorized dummy token
      await pscontract.addAuthorizedToken(await dummyToken.getAddress(), 18, 5_000n * precision); // 1 dummy token = 100,000 1XMM

      // Spender is authorized
      await pscontract.addAuthorizedUser(spender);

      // Spender gives allowance to smart contract for transfer of dummyToken
      await dummyToken.connect(spender).approve(await pscontract.getAddress(), 25n * decimalAdjustment);

      // Spender buys 1,000,000 1XMM tokens
      await pscontract.connect(spender).exchangeToken(dummyToken, 25n * decimalAdjustment);

      expect (await pscontract.isActive()).to.equal(false);
    });
});