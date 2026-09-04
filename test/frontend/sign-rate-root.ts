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
const RATE = "3170979198";

function buildTypes(height: number) {
  let rateOfferTreeFieldType = "RateOffer";
  for (let i = 0; i < height; i++) rateOfferTreeFieldType += "[2]";

  return {
    EIP712Domain: [
      { name: "chainId", type: "uint256" },
      { name: "verifyingContract", type: "address" },
    ],
    RateOfferTree: [{ name: "offerTree", type: rateOfferTreeFieldType }],
    CollateralParams: [
      { name: "token", type: "address" },
      { name: "lltv", type: "uint256" },
      { name: "liquidationCursor", type: "uint256" },
      { name: "oracle", type: "address" },
    ],
    Market: [
      { name: "chainId", type: "uint256" },
      { name: "midnight", type: "address" },
      { name: "loanToken", type: "address" },
      { name: "collateralParams", type: "CollateralParams[]" },
      { name: "maturity", type: "uint256" },
      { name: "rcfThreshold", type: "uint256" },
      { name: "enterGate", type: "address" },
      { name: "liquidatorGate", type: "address" },
    ],
    RateOffer: [
      { name: "market", type: "Market" },
      { name: "buy", type: "bool" },
      { name: "maker", type: "address" },
      { name: "start", type: "uint256" },
      { name: "expiry", type: "uint256" },
      { name: "startRate", type: "uint256" },
      { name: "expiryRate", type: "uint256" },
      { name: "group", type: "bytes32" },
      { name: "callback", type: "address" },
      { name: "callbackData", type: "bytes" },
      { name: "receiverIfMakerIsSeller", type: "address" },
      { name: "ratifier", type: "address" },
      { name: "reduceOnly", type: "bool" },
      { name: "maxUnits", type: "uint128" },
      { name: "maxAssets", type: "uint128" },
      { name: "continuousFeeCap", type: "uint256" },
    ],
  };
}

function defaultRateOffer(number: string) {
  return {
    market: {
      chainId: "1",
      midnight: ZERO_ADDR,
      loanToken: "0x" + number.repeat(40),
      collateralParams: [{ token: ZERO_ADDR, lltv: "0", liquidationCursor: "0", oracle: ZERO_ADDR }],
      maturity: "0",
      rcfThreshold: "0",
      enterGate: ZERO_ADDR,
      liquidatorGate: ZERO_ADDR,
    },
    buy: true,
    maker: ZERO_ADDR,
    start: "0",
    expiry: 2 ** 32,
    startRate: RATE,
    expiryRate: RATE,
    group: ZERO_B32,
    callback: ZERO_ADDR,
    callbackData: "0x",
    receiverIfMakerIsSeller: ZERO_ADDR,
    ratifier: RATIFIER,
    reduceOnly: false,
    maxUnits: "0",
    maxAssets: "0",
    continuousFeeCap: "0",
  };
}

function buildRateOfferTree() {
  return [
    [defaultRateOffer("1"), defaultRateOffer("2")],
    [defaultRateOffer("3"), defaultRateOffer("4")],
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

  const rateOfferTree = buildRateOfferTree();

  app.innerHTML = `
    <p>Connected: <code>${account}</code> &middot; Chain <code>${chainId}</code></p>
    <p>Ratifier: <code>${RATIFIER}</code> &middot; Height: <code>${HEIGHT}</code></p>

    <div class="field">
      <label for="offer">RateOfferTree (4 rate offers as RateOffer[2][2])</label>
      <textarea id="offer" spellcheck="false">${JSON.stringify(rateOfferTree, null, 2)}</textarea>
    </div>

    <button id="sign">Sign RateOfferTree</button>
    <pre id="result"></pre>
  `;

  $("sign").addEventListener("click", async () => {
    const resultEl = $("result");
    resultEl.textContent = "Waiting for wallet…";

    try {
      const offerData = JSON.parse(($("offer") as HTMLTextAreaElement).value);

      const typedData = {
        types: buildTypes(HEIGHT),
        primaryType: "RateOfferTree",
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
        `uint256 constant RATE = ${RATE};`,
        `uint8 constant RATE_SIG_V = ${v};`,
        `bytes32 constant RATE_SIG_R = ${r};`,
        `bytes32 constant RATE_SIG_S = ${s};`,
      ].join("\n");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      resultEl.textContent = `Error: ${msg}`;
    }
  });
}

main();
