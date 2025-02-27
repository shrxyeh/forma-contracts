import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { task } from "hardhat/config";
import type { TaskArguments } from "hardhat/types";

import type { XPromptNft } from "../../types/contracts/XPromptNft";
import type { XPromptNft__factory } from "../../types/factories/contracts/XPromptNft__factory";

task("deploy:XpromptNft").setAction(async function (taskArguments: TaskArguments, { ethers }) {
  const signers: SignerWithAddress[] = await ethers.getSigners();
  const xPromptNftFactory: XPromptNft__factory = <XPromptNft__factory>await ethers.getContractFactory("XPromptNft");
  const xPromptNft: XPromptNft = <XPromptNft>await xPromptNftFactory.connect(signers[0]).deploy();
  await xPromptNft.deployed();
  console.log("XPromptNft deployed to: ", xPromptNft.address);
});
