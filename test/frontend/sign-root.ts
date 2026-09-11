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
const START_RATE = "9512937594"; // ~30%/yr
const EXPIRY_RATE = "3170979198"; // ~10%/yr
const ALLOWED_TAKER = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC";

const DOMAIN_TYPE = [
  { name: "chainId", type: "uint256" },
  { name: "verifyingContract", type: "address" },
];

const COLLATERAL_PARAMS_TYPE = [
  { name: "token", type: "address" },
  { name: "lltv", type: "uint256" },
  { name: "liquidationCursor", type: "uint256" },
  { name: "oracle", type: "address" },
];

const MARKET_TYPE = [
  { name: "chainId", type: "uint256" },
  { name: "midnight", type: "address" },
  { name: "loanToken", type: "address" },
  { name: "collateralParams", type: "CollateralParams[]" },
  { name: "maturity", type: "uint256" },
  { name: "rcfThreshold", type: "uint256" },
  { name: "enterGate", type: "address" },
  { name: "liquidatorGate", type: "address" },
];

function buildOfferTypes(height: number) {
  let offerTreeFieldType = "Offer";
  for (let i = 0; i < height; i++) offerTreeFieldType += "[2]";

  return {
    EIP712Domain: DOMAIN_TYPE,
    OfferTree: [{ name: "offerTree", type: offerTreeFieldType }],
    CollateralParams: COLLATERAL_PARAMS_TYPE,
    Market: MARKET_TYPE,
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
      { name: "maxUnits", type: "uint128" },
      { name: "maxAssets", type: "uint128" },
      { name: "continuousFeeCap", type: "uint256" },
    ],
  };
}

function buildRateOfferTypes(height: number) {
  let rateOfferTreeFieldType = "RateOffer";
  for (let i = 0; i < height; i++) rateOfferTreeFieldType += "[2]";

  return {
    EIP712Domain: DOMAIN_TYPE,
    RateOfferTree: [{ name: "offerTree", type: rateOfferTreeFieldType }],
    CollateralParams: COLLATERAL_PARAMS_TYPE,
    Market: MARKET_TYPE,
    RateOffer: [
      { name: "market", type: "Market" },
      { name: "buy", type: "bool" },
      { name: "maker", type: "address" },
      { name: "start", type: "uint256" },
      { name: "expiry", type: "uint256" },
      { name: "startRate", type: "uint256" },
      { name: "expiryRate", type: "uint256" },
      { name: "allowedTaker", type: "address" },
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

function defaultMarket(number: string) {
  return {
    chainId: "1",
    midnight: ZERO_ADDR,
    loanToken: "0x" + number.repeat(40),
    collateralParams: [{ token: ZERO_ADDR, lltv: "0", liquidationCursor: "0", oracle: ZERO_ADDR }],
    maturity: "0",
    rcfThreshold: "0",
    enterGate: ZERO_ADDR,
    liquidatorGate: ZERO_ADDR,
  };
}

function defaultOffer(number: string) {
  return {
    market: defaultMarket(number),
    buy: false,
    maker: ZERO_ADDR,
    start: "0",
    expiry: 2 ** 32,
    tick: "0",
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

function defaultRateOffer(number: string) {
  return {
    market: defaultMarket(number),
    buy: true,
    maker: ZERO_ADDR,
    start: "0",
    expiry: 2 ** 32,
    startRate: START_RATE,
    expiryRate: EXPIRY_RATE,
    allowedTaker: ALLOWED_TAKER,
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

function buildOfferTree() {
  return [
    [defaultOffer("1"), defaultOffer("2")],
    [defaultOffer("3"), defaultOffer("4")],
  ];
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

function parseSig(sig: string) {
  return {
    r: "0x" + sig.slice(2, 66),
    s: "0x" + sig.slice(66, 130),
    v: parseInt(sig.slice(130, 132), 16),
  };
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

  app.innerHTML = `
    <p>Connected: <code>${account}</code> &middot; Chain <code>${chainId}</code></p>
    <p>Ratifier: <code>${RATIFIER}</code> &middot; Height: <code>${HEIGHT}</code></p>

    <div class="field">
      <label for="offer">OfferTree (4 offers as Offer[2][2])</label>
      <textarea id="offer" spellcheck="false">${JSON.stringify(buildOfferTree(), null, 2)}</textarea>
    </div>
    <button id="sign">Sign OfferTree</button>
    <pre id="result"></pre>

    <hr style="margin: 32px 0">

    <div class="field">
      <label for="rate-offer">RateOfferTree (4 rate offers as RateOffer[2][2])</label>
      <textarea id="rate-offer" spellcheck="false">${JSON.stringify(buildRateOfferTree(), null, 2)}</textarea>
    </div>
    <button id="sign-rate">Sign RateOfferTree</button>
    <pre id="rate-result"></pre>
  `;

  $("sign").addEventListener("click", async () => {
    const resultEl = $("result");
    resultEl.textContent = "Waiting for wallet…";
    try {
      const offerData = JSON.parse(($("offer") as HTMLTextAreaElement).value);
      const typedData = {
        types: buildOfferTypes(HEIGHT),
        primaryType: "OfferTree",
        domain: { chainId, verifyingContract: RATIFIER },
        message: { offerTree: offerData },
      };
      const sig = parseSig(
        (await window.ethereum!.request({
          method: "eth_signTypedData_v4",
          params: [account, JSON.stringify(typedData)],
        })) as string,
      );
      resultEl.textContent = [
        `address constant ACCOUNT = ${account};`,
        `uint8 constant SIG_V = ${sig.v};`,
        `bytes32 constant SIG_R = ${sig.r};`,
        `bytes32 constant SIG_S = ${sig.s};`,
      ].join("\n");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      $("result").textContent = `Error: ${msg}`;
    }
  });

  $("sign-rate").addEventListener("click", async () => {
    const resultEl = $("rate-result");
    resultEl.textContent = "Waiting for wallet…";
    try {
      const offerData = JSON.parse(($("rate-offer") as HTMLTextAreaElement).value);
      const typedData = {
        types: buildRateOfferTypes(HEIGHT),
        primaryType: "RateOfferTree",
        domain: { chainId, verifyingContract: RATIFIER },
        message: { offerTree: offerData },
      };
      const sig = parseSig(
        (await window.ethereum!.request({
          method: "eth_signTypedData_v4",
          params: [account, JSON.stringify(typedData)],
        })) as string,
      );
      resultEl.textContent = [
        `address constant RATE_ACCOUNT = ${account};`,
        `uint256 constant START_RATE = ${START_RATE};`,
        `uint256 constant EXPIRY_RATE = ${EXPIRY_RATE};`,
        `address constant ALLOWED_TAKER = ${ALLOWED_TAKER};`,
        `uint8 constant RATE_SIG_V = ${sig.v};`,
        `bytes32 constant RATE_SIG_R = ${sig.r};`,
        `bytes32 constant RATE_SIG_S = ${sig.s};`,
      ].join("\n");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      $("rate-result").textContent = `Error: ${msg}`;
    }
  });
}

main();
