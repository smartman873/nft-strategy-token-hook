import { ethers } from "ethers";
import vaultAbi from "../../shared/abis/StrategyVault.json";
import erc20Abi from "../../shared/abis/ERC20Minimal.json";

let provider;
let signer;

const els = {
  connect: document.getElementById("connect"),
  wallet: document.getElementById("wallet"),
  vault: document.getElementById("vault"),
  asset: document.getElementById("asset"),
  poolId: document.getElementById("poolId"),
  load: document.getElementById("load"),
  state: document.getElementById("state"),
  log: document.getElementById("log"),
  depositAssets: document.getElementById("depositAssets"),
  redeemShares: document.getElementById("redeemShares"),
  maxCost: document.getElementById("maxCost"),
  deposit: document.getElementById("deposit"),
  redeem: document.getElementById("redeem"),
  acquire: document.getElementById("acquire")
};

function appendLog(msg) {
  els.log.textContent = `${new Date().toISOString()}  ${msg}\n${els.log.textContent}`;
}

async function connect() {
  if (!window.ethereum) {
    appendLog("No EIP-1193 wallet found");
    return;
  }
  provider = new ethers.BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  els.wallet.textContent = await signer.getAddress();
}

function getContracts() {
  if (!signer) {
    throw new Error("Connect wallet first");
  }
  const vault = new ethers.Contract(els.vault.value, vaultAbi, signer);
  const asset = new ethers.Contract(els.asset.value, erc20Abi, signer);
  return { vault, asset };
}

async function loadState() {
  const { vault, asset } = getContracts();
  const account = await signer.getAddress();

  const [shareTokenAddr, assetsInVault, accountAssets, policy] = await Promise.all([
    vault.shareToken(),
    vault.totalManagedAssets(),
    asset.balanceOf(account),
    vault.poolPolicies(els.poolId.value)
  ]);

  const payload = {
    account,
    shareToken: shareTokenAddr,
    totalManagedAssets: assetsInVault.toString(),
    accountAssetBalance: accountAssets.toString(),
    policy: {
      acquireThreshold: policy[0].toString(),
      valuationMode: policy[1].toString(),
      policyNonce: policy[2].toString(),
      revenueReserve: policy[3].toString(),
      nftCount: policy[4].toString()
    }
  };

  els.state.textContent = JSON.stringify(payload, null, 2);
}

async function deposit() {
  const { vault, asset } = getContracts();
  const account = await signer.getAddress();
  const amount = ethers.parseUnits(els.depositAssets.value, 18);

  const approveTx = await asset.approve(vault.target, amount);
  await approveTx.wait();

  const tx = await vault.deposit(amount, account, 0n);
  const receipt = await tx.wait();
  appendLog(`deposit tx: ${receipt.hash}`);
}

async function redeem() {
  const { vault } = getContracts();
  const account = await signer.getAddress();
  const shares = ethers.parseUnits(els.redeemShares.value, 18);

  const tx = await vault.redeem(shares, account, 0n);
  const receipt = await tx.wait();
  appendLog(`redeem tx: ${receipt.hash}`);
}

async function acquire() {
  const { vault } = getContracts();
  const maxCost = BigInt(els.maxCost.value);
  const tx = await vault.acquireNFT(els.poolId.value, maxCost);
  const receipt = await tx.wait();
  appendLog(`acquire tx: ${receipt.hash}`);
}

els.connect.addEventListener("click", () => connect().catch((e) => appendLog(e.message)));
els.load.addEventListener("click", () => loadState().catch((e) => appendLog(e.message)));
els.deposit.addEventListener("click", () => deposit().catch((e) => appendLog(e.message)));
els.redeem.addEventListener("click", () => redeem().catch((e) => appendLog(e.message)));
els.acquire.addEventListener("click", () => acquire().catch((e) => appendLog(e.message)));
