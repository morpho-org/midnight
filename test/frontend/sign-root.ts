export {};

declare global {
  interface Window {
    ethereum?: {
      request(args: { method: string; params?: unknown[] }): Promise<unknown>;
      on(event: string, handler: (...args: unknown[]) => void): void;
    };
  }
}

const ZERO_ADDR = "0x0000000000000000000000000000000000000000";
const ZERO_B32 = "0x" + "00".repeat(32);
const RATIFIER = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB";
const HEIGHT = 2;

/** EIP-712 type definitions matching EcrecoverRatifier's verification logic. */
function buildTypes(height: number) {
  let offerTreeFieldType = "Offer";
  for (let i = 0; i < height; i++) offerTreeFieldType += "[2]";

  return {
    EIP712Domain: [
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" },
    ],
    OfferTree: [{ name: "offerTree", type: offerTreeFieldType }],
    CollateralParams: [
      { name: "token", type: "address" },
      { name: "lltv", type: "uint256" },
      { name: "maxLif", type: "uint256" },
      { name: "oracle", type: "address" },
    ],
    Market: [
      { name: "loanToken", type: "address" },
      { name: "collateralParams", type: "CollateralParams[]" },
      { name: "maturity", type: "uint256" },
      { name: "rcfThreshold", type: "uint256" },
      { name: "enterGate", type: "address" },
      { name: "liquidatorGate", type: "address" },
    ],
    Offer: [
      { name: "market", type: "Market" },
      { name: "buy", type: "bool" },
      { name: "maker", type: "address" },
      { name: "start", type: "uint256" },
      { name: "expiry", type: "uint256" },
      { name: "tick", type: "uint256" },
      { name: "group", type: "bytes32" },
      { name: "callback", type: "address" },
      { name: "callbackData", type: "bytes" },
      { name: "receiverIfMakerIsSeller", type: "address" },
      { name: "ratifier", type: "address" },
      { name: "reduceOnly", type: "bool" },
      { name: "maxUnits", type: "uint256" },
      { name: "maxAssets", type: "uint256" },
    ],
  };
}

function defaultOffer(number: string) {
  return {
    market: {
      loanToken: "0x" + number.repeat(40),
      collateralParams: [{token: ZERO_ADDR, lltv: "0", maxLif: "0", oracle: ZERO_ADDR}],
      maturity: "0",
      rcfThreshold: "0",
      enterGate: ZERO_ADDR,
      liquidatorGate: ZERO_ADDR,
    },
    buy: false,
    maker: ZERO_ADDR,
    start: "0",
    expiry: 2**32,
    tick: "0",
    group: ZERO_B32,
    callback: ZERO_ADDR,
    callbackData: "0x",
    receiverIfMakerIsSeller: ZERO_ADDR,
    ratifier: RATIFIER,
    reduceOnly: false,
    maxUnits: "0",
    maxAssets: "0",
  };
}

// WARNING: The tree should be built by sorting the nodes in ascending order of their hash.
function buildOfferTree() {
  return [
    [defaultOffer("2"), defaultOffer("4")],
    [defaultOffer("3"), defaultOffer("1")],
  ];
}

function $(id: string) {
  return document.getElementById(id)!;
}

async function main() {
  const app = $("app");

  if (!window.ethereum) {
    app.innerHTML = `<p class="error">No injected wallet found. Install MetaMask or another browser wallet.</p>`;
    return;
  }

  const accounts = (await window.ethereum.request({ method: "eth_requestAccounts" })) as string[];
  const account = accounts[0].toLowerCase();
  const chainId = Number(await window.ethereum.request({ method: "eth_chainId" }));

  const offerTree = buildOfferTree();

  app.innerHTML = `
    <p>Connected: <code>${account}</code> &middot; Chain <code>${chainId}</code></p>
    <p>Ratifier: <code>${RATIFIER}</code> &middot; Height: <code>${HEIGHT}</code></p>

    <div class="field">
      <label for="offer">OfferTree (4 offers as Offer[2][2])</label>
      <textarea id="offer" spellcheck="false">${JSON.stringify(offerTree, null, 2)}</textarea>
    </div>

    <button id="sign">Sign OfferTree</button>
    <pre id="result"></pre>
  `;

  $("sign").addEventListener("click", async () => {
    const resultEl = $("result");
    resultEl.textContent = "Waiting for wallet…";

    try {
      const offerData = JSON.parse(
        ($("offer") as HTMLTextAreaElement).value,
      );

      const typedData = {
        types: buildTypes(HEIGHT),
        primaryType: "OfferTree",
        domain: { chainId, verifyingContract: RATIFIER },
        message: { offerTree: offerData },
      };

      const sig = (await window.ethereum!.request({
        method: "eth_signTypedData_v4",
        params: [account, JSON.stringify(typedData)],
      })) as string;

      const r = "0x" + sig.slice(2, 66);
      const s = "0x" + sig.slice(66, 130);
      const v = parseInt(sig.slice(130, 132), 16);

      resultEl.textContent = [
        `address constant ACCOUNT = ${account};`,
        `uint8 constant SIG_V = ${v};`,
        `bytes32 constant SIG_R = ${r};`,
        `bytes32 constant SIG_S = ${s};`,
      ].join("\n");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      resultEl.textContent = `Error: ${msg}`;
    }
  });
}

main();
