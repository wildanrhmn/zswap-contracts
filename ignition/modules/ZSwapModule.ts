import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "ethers";

const ZSwapModule = buildModule("ZSwapModule", (m) => {
  const mockUSD = m.contract("MockUSD", [m.getAccount(0)])
  const mockUtility = m.contract("MockUtility", [m.getAccount(0)]);

  const zswap = m.contract("ZSwap", [m.getAccount(0)]);

  const mintAmount = parseEther("1000000");
  m.call(mockUSD, "mint", [m.getAccount(0), mintAmount]);
  m.call(mockUtility, "mint", [m.getAccount(0), mintAmount]);

  return {
    mockUSD,
    mockUtility,
    zswap
  };
});

export default ZSwapModule; 