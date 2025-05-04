import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";

describe("ZSwap", function () {
  async function deployContractsFixture() {
    const [owner, user1, user2] = await hre.ethers.getSigners();

    const MockUSD = await hre.ethers.getContractFactory("MockUSD");
    const MockUtility = await hre.ethers.getContractFactory("MockUtility");

    const mockUSD = await MockUSD.deploy(owner.address);
    const mockUtility = await MockUtility.deploy(owner.address);

    const ZSwap = await hre.ethers.getContractFactory("ZSwap");
    const zswap = await ZSwap.deploy(owner.address);

    const mintAmount = ethers.parseEther("1000000");
    await mockUSD.mint(user1.address, mintAmount);
    await mockUtility.mint(user1.address, mintAmount);
    await mockUSD.mint(user2.address, mintAmount);
    await mockUtility.mint(user2.address, mintAmount);

    return { zswap, mockUSD, mockUtility, owner, user1, user2 };
  }

  describe("Pair Creation", function () {
    it("Should create a new pair", async function () {
      const { zswap, mockUSD, mockUtility } = await loadFixture(deployContractsFixture);

      await expect(zswap.createPair(mockUSD.target, mockUtility.target))
        .to.emit(zswap, "PairCreated")
        .withArgs(mockUSD.target, mockUtility.target);

      const pair = await zswap.getPair(mockUSD.target, mockUtility.target);
      expect(pair.exists).to.be.true;
    });

    it("Should not create duplicate pairs", async function () {
      const { zswap, mockUSD, mockUtility } = await loadFixture(deployContractsFixture);

      await zswap.createPair(mockUSD.target, mockUtility.target);
      await expect(zswap.createPair(mockUSD.target, mockUtility.target))
        .to.be.revertedWith("ZSwap: PAIR_EXISTS");
    });
  });

  describe("Liquidity", function () {
    it("Should add liquidity to a pair", async function () {
      const { zswap, mockUSD, mockUtility, user1 } = await loadFixture(deployContractsFixture);
      
      await zswap.createPair(mockUSD.target, mockUtility.target);

      const amount = ethers.parseEther("1000");
      await mockUSD.connect(user1).approve(zswap.target, amount);
      await mockUtility.connect(user1).approve(zswap.target, amount);

      await expect(zswap.connect(user1).addLiquidity(
        mockUSD.target,
        mockUtility.target,
        amount,
        amount,
        0,
        0
      )).to.emit(zswap, "LiquidityAdded");

      const pair = await zswap.getPair(mockUSD.target, mockUtility.target);
      expect(pair.reserve0).to.equal(amount);
      expect(pair.reserve1).to.equal(amount);
    });

    it("Should remove liquidity from a pair", async function () {
      const { zswap, mockUSD, mockUtility, user1 } = await loadFixture(deployContractsFixture);
      
      await zswap.createPair(mockUSD.target, mockUtility.target);
      const amount = ethers.parseEther("1000");
      await mockUSD.connect(user1).approve(zswap.target, amount);
      await mockUtility.connect(user1).approve(zswap.target, amount);
      await zswap.connect(user1).addLiquidity(
        mockUSD.target,
        mockUtility.target,
        amount,
        amount,
        0,
        0
      );

      const userLiquidity = await zswap.getUserLiquidity(mockUSD.target, mockUtility.target, user1.address);
      
      await expect(zswap.connect(user1).removeLiquidity(
        mockUSD.target,
        mockUtility.target,
        userLiquidity.amount,
        0,
        0
      )).to.emit(zswap, "LiquidityRemoved");
    });
  });

  describe("Swapping", function () {
    it("Should swap tokens", async function () {
      const { zswap, mockUSD, mockUtility, user1 } = await loadFixture(deployContractsFixture);
      
      await zswap.createPair(mockUSD.target, mockUtility.target);
      const liquidityAmount = ethers.parseEther("1000");
      await mockUSD.connect(user1).approve(zswap.target, liquidityAmount);
      await mockUtility.connect(user1).approve(zswap.target, liquidityAmount);
      await zswap.connect(user1).addLiquidity(
        mockUSD.target,
        mockUtility.target,
        liquidityAmount,
        liquidityAmount,
        0,
        0
      );

      const swapAmount = ethers.parseEther("100");
      await mockUSD.connect(user1).approve(zswap.target, swapAmount);
      
      const path = [mockUSD.target, mockUtility.target];
      await expect(zswap.connect(user1).swap(
        swapAmount,
        0,
        path,
        user1.address
      )).to.emit(zswap, "Swap");
    });

    it("Should fail with invalid path", async function () {
      const { zswap, mockUSD, user1 } = await loadFixture(deployContractsFixture);
      
      const path = [mockUSD.target];
      await expect(zswap.connect(user1).swap(
        ethers.parseEther("100"),
        0,
        path,
        user1.address
      )).to.be.revertedWith("ZSwap: INVALID_PATH");
    });
  });

  describe("Fee Management", function () {
    it("Should allow owner to update swap fee", async function () {
      const { zswap, owner } = await loadFixture(deployContractsFixture);
      
      const newFee = 50;
      await expect(zswap.connect(owner).setSwapFee(newFee))
        .to.emit(zswap, "FeeUpdated")
        .withArgs(30, newFee);
      
      expect(await zswap.swapFee()).to.equal(newFee);
    });

    it("Should not allow non-owner to update swap fee", async function () {
      const { zswap, user1 } = await loadFixture(deployContractsFixture);
      
      await expect(zswap.connect(user1).setSwapFee(50))
        .to.be.revertedWithCustomError(zswap, "OwnableUnauthorizedAccount")
        .withArgs(user1.address);
    });

    it("Should not allow fee to be set too high", async function () {
      const { zswap, owner } = await loadFixture(deployContractsFixture);
      
      await expect(zswap.connect(owner).setSwapFee(501))
        .to.be.revertedWith("ZSwap: FEE_TOO_HIGH");
    });
  });
}); 