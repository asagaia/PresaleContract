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

describe('Test membersonly functions', function () {
    it('Only owner can add authorized user', async function () {
        const [owner, spender, pscontract, dummy1XMM] = await deploy();

        expect(await pscontract.connect(spender).isAuthorized()).to.be.false;
        await expect(pscontract.connect(spender).addAuthorizedUser(spender.address)).to.be.revertedWith('E0');
        await expect(pscontract.addAuthorizedUser(spender.address)).to.emit(pscontract, "AuthorizedUserAdded");
        expect(await pscontract.connect(spender).isAuthorized()).to.be.true;
    });

    it('Can add a list of authorized users', async function () {
        const [owner, spender, pscontract, dummy1XMM] = await deploy();

        await pscontract.addAuthorizedUsers([
            spender.address,
            "0x1234567890123456789012345678901234567890",
            "0x1234567890123456789012345678901234567809",
            "0x1234567890123456789012345678901234568709",
        ]);

        expect(await pscontract.connect(spender).isAuthorized()).to.be.true;
        expect(await pscontract["isAuthorized(address)"]("0x1234567890123456789012345678901234567809")).to.be.true;
        expect(await pscontract["isAuthorized(address)"]("0x1234567890123456789012345678901234568709")).to.be.true;
    });

    it('Does not change if an exiting user is added', async function () {
        const [owner, spender, pscontract, dummy1XMM] = await deploy();

        await pscontract.addAuthorizedUser(spender.address);
        await pscontract.addAuthorizedUser(spender.address);
        expect(await pscontract.connect(spender).isAuthorized()).to.be.true;
    });
});