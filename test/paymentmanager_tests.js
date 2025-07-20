const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
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

  const dummy1XMMAddress = await dummy1XMM.getAddress();
  const pscontract = await contractFactory.deploy(owner, dummy1XMMAddress, timeNow, timeNow + 3600000, 500);

  return [manager, spender, pscontract, dummy1XMM, owner];
}

describe('Test payment manager functions', function () {
    it('Has the right prices', async function () {
        const [owner, spender, pscontract, dummy1XMM] = await deploy();

        await expect(pscontract.getPrice("0x1234567890123456789012345678901234567890")).to.be.revertedWith('E1'); // pscontract not authorized

        // 1ETH = $2,450
        // 1XMM = $0.05
        expect(await pscontract.getPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")).to.equal(49_000n * precision);
        expect(await pscontract.getPrice("0xdAC17F958D2ee523a2206206994597C13D831ec7")).to.equal(20n * precision);
    });

    it('Can add new authorized token', async function () {
        const [owner, spender, pscontract, dummy1XMM] = await deploy();

        await expect(pscontract.addAuthorizedToken("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 18, 2450)).to.be.revertedWith('E2'); // Already authorized

        await pscontract.addAuthorizedToken("0x1234567890123456789012345678901234567890", 18, 100);
        expect(await pscontract.getPrice("0x1234567890123456789012345678901234567890")).to.equal(2_000n); // 100 / 0.05
    });

    it('Can set new price for a token', async function () {
        const [owner, spender, pscontract, dummy1XMM] = await deploy();

        await expect(pscontract.connect(spender).setPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 26_000_000)).to.be.revertedWith('E0'); // Only owner
        await expect(pscontract.setPrice("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", 11_000)).to.be.revertedWith('E3'); // Not USD

        await pscontract.setPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 26_000_000);
        expect(await pscontract.getPrice("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")).to.equal(2_600n * 20n * precision); // 26_000_000 / 0.05
    });

    it('Can return the list of authorized tokens', async function() {
        const [owner, spender, pscontract, dummy1XMM] = await deploy();

        const authorizedTokens = await pscontract.authorizedTokens();
        expect(authorizedTokens.length).to.equal(4);
        // Address at index 2 is USDC address
        expect(authorizedTokens[2]).to.equal("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
    });
});