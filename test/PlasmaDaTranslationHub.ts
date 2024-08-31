import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { ignition, network, viem } from "hardhat";
import PlasmaDaTranslationHubModule from "../ignition/modules/PlasmaDaTranslationHub";
import { WalletClient, namehash } from "viem";
import { expect } from "chai";

// Mock up data
const DATA_HASH_1 = namehash("DATA_HASH_1");
const DATA_HASH_2 = namehash("DATA_HASH_2");
const DA_1 = namehash("DA_1");
const DA_2 = namehash("DA_2");
const CID_1 = "0x1234";
const CID_2 = "0xabcdef1234";
const CID_3 = "0xcdef1234";

async function deployFixture() {
  return ignition.deploy(PlasmaDaTranslationHubModule);
}

async function signDelegatedSubmit(
  signer: WalletClient,
  verifyingContract: `0x${string}`,
  dataHash: `0x${string}`,
  da: `0x${string}`,
  cid: `0x${string}`
): Promise<`0x${string}`> {
  const signature = await signer.signTypedData({
    account: signer.account!.address,
    domain: {
      name: "PlasmaDaTranslationHub",
      version: "1",
      chainId: network.config.chainId,
      verifyingContract,
    },
    types: {
      PlasmaDaSubmit: [
        { name: "dataHash", type: "bytes32" },
        { name: "da", type: "bytes32" },
        { name: "cid", type: "bytes" },
      ],
    },
    primaryType: "PlasmaDaSubmit",
    message: {
      dataHash,
      da,
      cid,
    },
  });

  return signature;
}

describe("PlasmaDaTranslationHub", function () {
  let signers: WalletClient[];

  before(async () => {
    signers = await viem.getWalletClients();
  });

  describe("Basic Submission", () => {
    it("Can submit", async function () {
      const { hub } = await loadFixture(deployFixture);

      await hub.write.submit([DATA_HASH_1, DA_1, CID_1]);
      await hub.write.submit([DATA_HASH_2, DA_2, CID_2]);
      await hub.write.submit([DATA_HASH_1, DA_2, CID_3]);

      {
        const cid1 = await hub.read.translation([
          signers[0].account!.address,
          DATA_HASH_1,
          DA_1,
        ]);

        const cid2 = await hub.read.translation([
          signers[0].account!.address,
          DATA_HASH_2,
          DA_2,
        ]);

        const cid3 = await hub.read.translation([
          signers[0].account!.address,
          DATA_HASH_1,
          DA_2,
        ]);

        expect(cid1).to.equal(CID_1);
        expect(cid2).to.equal(CID_2);
        expect(cid3).to.equal(CID_3);

        const daCid1 = await hub.read.get([
          signers[0].account!.address,
          DATA_HASH_1,
        ]);
        const daCid2 = await hub.read.get([
          signers[0].account!.address,
          DATA_HASH_2,
        ]);

        expect(daCid1.length).to.equal(2);
        expect(daCid2.length).to.equal(1);

        expect(daCid1[0].da).to.equal(DA_1);
        expect(daCid1[1].da).to.equal(DA_2);
        expect(daCid2[0].da).to.equal(DA_2);

        expect(daCid1[0].cid).to.equal(CID_1);
        expect(daCid1[1].cid).to.equal(CID_3);
        expect(daCid2[0].cid).to.equal(CID_2);
      }
    });

    it("Can batch submit", async function () {
      const { hub } = await loadFixture(deployFixture);

      await hub.write.batchSubmit([
        [
          {
            dataHash: DATA_HASH_1,
            da: DA_1,
            cid: CID_1,
          },
          {
            dataHash: DATA_HASH_1,
            da: DA_2,
            cid: CID_3,
          },
          {
            dataHash: DATA_HASH_2,
            da: DA_2,
            cid: CID_2,
          },
        ],
      ]);

      {
        const cid1 = await hub.read.translation([
          signers[0].account!.address,
          DATA_HASH_1,
          DA_1,
        ]);

        const cid2 = await hub.read.translation([
          signers[0].account!.address,
          DATA_HASH_2,
          DA_2,
        ]);

        const cid3 = await hub.read.translation([
          signers[0].account!.address,
          DATA_HASH_1,
          DA_2,
        ]);

        expect(cid1).to.equal(CID_1);
        expect(cid2).to.equal(CID_2);
        expect(cid3).to.equal(CID_3);

        const daCid1 = await hub.read.get([
          signers[0].account!.address,
          DATA_HASH_1,
        ]);
        const daCid2 = await hub.read.get([
          signers[0].account!.address,
          DATA_HASH_2,
        ]);

        expect(daCid1.length).to.equal(2);
        expect(daCid2.length).to.equal(1);

        expect(daCid1[0].da).to.equal(DA_1);
        expect(daCid1[1].da).to.equal(DA_2);
        expect(daCid2[0].da).to.equal(DA_2);

        expect(daCid1[0].cid).to.equal(CID_1);
        expect(daCid1[1].cid).to.equal(CID_3);
        expect(daCid2[0].cid).to.equal(CID_2);
      }
    });

    it("Can't override existing submission", async function () {
      const { hub } = await loadFixture(deployFixture);

      await hub.write.submit([DATA_HASH_1, DA_1, CID_1]);

      expect(hub.write.submit([DATA_HASH_1, DA_1, CID_2])).to.be.rejectedWith(
        "DuplicatedSubmission()"
      );

      const cid1 = await hub.read.translation([
        signers[0].account!.address,
        DATA_HASH_1,
        DA_1,
      ]);

      expect(cid1).to.equal(CID_1);
    });
  });

  describe("Delegated Submission", () => {
    it("Can submit", async function () {
      const { hub } = await loadFixture(deployFixture);

      await hub.write.delegatedSubmit([
        signers[1].account!.address,
        {
          dataHash: DATA_HASH_1,
          da: DA_1,
          cid: CID_1,
          signature: await signDelegatedSubmit(
            signers[1],
            hub.address,
            DATA_HASH_1,
            DA_1,
            CID_1
          ),
        },
      ]);
      await hub.write.delegatedSubmit([
        signers[1].account!.address,
        {
          dataHash: DATA_HASH_2,
          da: DA_2,
          cid: CID_2,
          signature: await signDelegatedSubmit(
            signers[1],
            hub.address,
            DATA_HASH_2,
            DA_2,
            CID_2
          ),
        },
      ]);
      await hub.write.delegatedSubmit([
        signers[2].account!.address,
        {
          dataHash: DATA_HASH_1,
          da: DA_1,
          cid: CID_3,
          signature: await signDelegatedSubmit(
            signers[2],
            hub.address,
            DATA_HASH_1,
            DA_1,
            CID_3
          ),
        },
      ]);
      await hub.write.delegatedSubmit([
        signers[1].account!.address,
        {
          dataHash: DATA_HASH_1,
          da: DA_2,
          cid: CID_3,
          signature: await signDelegatedSubmit(
            signers[1],
            hub.address,
            DATA_HASH_1,
            DA_2,
            CID_3
          ),
        },
      ]);

      {
        const cid1 = await hub.read.translation([
          signers[1].account!.address,
          DATA_HASH_1,
          DA_1,
        ]);

        const cid2 = await hub.read.translation([
          signers[1].account!.address,
          DATA_HASH_2,
          DA_2,
        ]);

        const cid3 = await hub.read.translation([
          signers[1].account!.address,
          DATA_HASH_1,
          DA_2,
        ]);

        const cid32 = await hub.read.translation([
          signers[2].account!.address,
          DATA_HASH_1,
          DA_1,
        ]);

        expect(cid1).to.equal(CID_1);
        expect(cid2).to.equal(CID_2);
        expect(cid3).to.equal(CID_3);
        expect(cid32).to.equal(CID_3);

        const daCid1 = await hub.read.get([
          signers[1].account!.address,
          DATA_HASH_1,
        ]);
        const daCid2 = await hub.read.get([
          signers[1].account!.address,
          DATA_HASH_2,
        ]);
        const daCid3 = await hub.read.get([
          signers[2].account!.address,
          DATA_HASH_1,
        ]);

        expect(daCid1.length).to.equal(2);
        expect(daCid2.length).to.equal(1);
        expect(daCid3.length).to.equal(1);

        expect(daCid1[0].da).to.equal(DA_1);
        expect(daCid1[1].da).to.equal(DA_2);
        expect(daCid2[0].da).to.equal(DA_2);
        expect(daCid3[0].da).to.equal(DA_1);

        expect(daCid1[0].cid).to.equal(CID_1);
        expect(daCid1[1].cid).to.equal(CID_3);
        expect(daCid2[0].cid).to.equal(CID_2);
        expect(daCid3[0].cid).to.equal(CID_3);
      }
    });

    it("Can batch submit", async function () {
      const { hub } = await loadFixture(deployFixture);

      await hub.write.batchDelegatedSubmit([
        signers[1].account!.address,
        [
          {
            dataHash: DATA_HASH_1,
            da: DA_1,
            cid: CID_1,
            signature: await signDelegatedSubmit(
              signers[1],
              hub.address,
              DATA_HASH_1,
              DA_1,
              CID_1
            ),
          },
          {
            dataHash: DATA_HASH_2,
            da: DA_2,
            cid: CID_2,
            signature: await signDelegatedSubmit(
              signers[1],
              hub.address,
              DATA_HASH_2,
              DA_2,
              CID_2
            ),
          },
          {
            dataHash: DATA_HASH_1,
            da: DA_2,
            cid: CID_3,
            signature: await signDelegatedSubmit(
              signers[1],
              hub.address,
              DATA_HASH_1,
              DA_2,
              CID_3
            ),
          },
        ],
      ]);

      await hub.write.batchDelegatedSubmit([
        signers[2].account!.address,
        [
          {
            dataHash: DATA_HASH_1,
            da: DA_1,
            cid: CID_3,
            signature: await signDelegatedSubmit(
              signers[2],
              hub.address,
              DATA_HASH_1,
              DA_1,
              CID_3
            ),
          },
        ]
      ]);

      {
        const cid1 = await hub.read.translation([
          signers[1].account!.address,
          DATA_HASH_1,
          DA_1,
        ]);

        const cid2 = await hub.read.translation([
          signers[1].account!.address,
          DATA_HASH_2,
          DA_2,
        ]);

        const cid3 = await hub.read.translation([
          signers[1].account!.address,
          DATA_HASH_1,
          DA_2,
        ]);

        const cid32 = await hub.read.translation([
          signers[2].account!.address,
          DATA_HASH_1,
          DA_1,
        ]);

        expect(cid1).to.equal(CID_1);
        expect(cid2).to.equal(CID_2);
        expect(cid3).to.equal(CID_3);
        expect(cid32).to.equal(CID_3);

        const daCid1 = await hub.read.get([
          signers[1].account!.address,
          DATA_HASH_1,
        ]);
        const daCid2 = await hub.read.get([
          signers[1].account!.address,
          DATA_HASH_2,
        ]);
        const daCid3 = await hub.read.get([
          signers[2].account!.address,
          DATA_HASH_1,
        ]);

        expect(daCid1.length).to.equal(2);
        expect(daCid2.length).to.equal(1);
        expect(daCid3.length).to.equal(1);

        expect(daCid1[0].da).to.equal(DA_1);
        expect(daCid1[1].da).to.equal(DA_2);
        expect(daCid2[0].da).to.equal(DA_2);
        expect(daCid3[0].da).to.equal(DA_1);

        expect(daCid1[0].cid).to.equal(CID_1);
        expect(daCid1[1].cid).to.equal(CID_3);
        expect(daCid2[0].cid).to.equal(CID_2);
        expect(daCid3[0].cid).to.equal(CID_3);
      }
    });
  });
});
