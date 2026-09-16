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
const ALLOWED_TAKER = "0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa";
const PRICE_RATIFIER = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC";
const RATE_RATIFIER = "0xDDdDddDdDdddDDddDDddDDDDdDdDDdDDdDDDDDDd";
const HEIGHT = 2;

// The signed message commits to the tree's height, so it is part of the type: Offer[2][2] for a height of 2.
function offerTreeType(offerType: keyof typeof OFFER_TYPES, height: number) {
  return offerType + "[2]".repeat(height);
}

const COMMON_TYPES = {
  EIP712Domain: [
    { name: "chainId", type: "uint256" },
    { name: "verifyingContract", type: "address" },
  ],
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
};

const OFFER_HEAD = [
  { name: "market", type: "Market" },
  { name: "buy", type: "bool" },
  { name: "maker", type: "address" },
  { name: "start", type: "uint256" },
  { name: "expiry", type: "uint256" },
];
const OFFER_TAIL = [
  { name: "group", type: "bytes32" },
  { name: "callback", type: "address" },
  { name: "callbackData", type: "bytes" },
  { name: "receiverIfMakerIsSeller", type: "address" },
  { name: "ratifier", type: "address" },
  { name: "reduceOnly", type: "bool" },
  { name: "maxUnits", type: "uint128" },
  { name: "maxAssets", type: "uint128" },
  { name: "continuousFeeCap", type: "uint256" },
];

const OFFER_TYPES = {
  /** EcrecoverRatifier: the offer as Midnight defines it. */
  Offer: [...OFFER_HEAD, { name: "tick", type: "uint256" }, ...OFFER_TAIL],
  /** PriceRatifierV1: the offer with an added allowedTaker. */
  PriceRatifierV1Offer: [
    ...OFFER_HEAD,
    { name: "tick", type: "uint256" },
    { name: "allowedTaker", type: "address" },
    ...OFFER_TAIL,
  ],
  /** RateRatifierV1: the offer with tick replaced by rate, and an added allowedTaker. */
  RateRatifierV1Offer: [
    ...OFFER_HEAD,
    { name: "rate", type: "uint256" },
    { name: "allowedTaker", type: "address" },
    ...OFFER_TAIL,
  ],
};

function defaultOffer(number: string, offerType: keyof typeof OFFER_TYPES, account: string) {
  const offer: Record<string, unknown> = {
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
    buy: offerType !== "Offer",
    maker: offerType === "Offer" ? ZERO_ADDR : account,
    start: "0",
    expiry: 2 ** 32,
  };

  if (offerType === "RateRatifierV1Offer") offer.rate = "0";
  else offer.tick = "0";
  if (offerType !== "Offer") offer.allowedTaker = ALLOWED_TAKER;

  return {
    ...offer,
    group: ZERO_B32,
    callback: ZERO_ADDR,
    callbackData: "0x",
    receiverIfMakerIsSeller: ZERO_ADDR,
    ratifier:
      offerType === "Offer" ? RATIFIER : offerType === "PriceRatifierV1Offer" ? PRICE_RATIFIER : RATE_RATIFIER,
    reduceOnly: false,
    maxUnits: "0",
    maxAssets: "0",
    continuousFeeCap: "0",
  };
}

function buildOfferTree(offerType: keyof typeof OFFER_TYPES, account: string) {
  return [
    [defaultOffer("1", offerType, account), defaultOffer("2", offerType, account)],
    [defaultOffer("3", offerType, account), defaultOffer("4", offerType, account)],
  ];
}

const NONCE = "0";
const DEADLINE = String(2 ** 32);

type Mode = {
  label: string;
  verifyingContract: string;
  offerType: keyof typeof OFFER_TYPES;
  primaryType: string;
  prefix: string;
  types(account: string): Record<string, { name: string; type: string }[]>;
  message(account: string, offerTree: unknown): Record<string, unknown>;
};

const MODES: Record<string, Mode> = {
  ecrecover: {
    label: "EcrecoverRatifier — OfferTree",
    verifyingContract: RATIFIER,
    offerType: "Offer",
    primaryType: "OfferTree",
    prefix: "",
    types: () => ({
      ...COMMON_TYPES,
      OfferTree: [{ name: "offerTree", type: offerTreeType("Offer", HEIGHT) }],
      Offer: OFFER_TYPES.Offer,
    }),
    message: (_account, offerTree) => ({ offerTree }),
  },
  price: {
    label: "PriceRatifierV1 — SetIsRootRatified",
    verifyingContract: PRICE_RATIFIER,
    offerType: "PriceRatifierV1Offer",
    primaryType: "SetIsRootRatified",
    prefix: "PRICE_",
    types: () => ({
      ...COMMON_TYPES,
      SetIsRootRatified: [
        { name: "maker", type: "address" },
        { name: "offerTree", type: offerTreeType("PriceRatifierV1Offer", HEIGHT) },
        { name: "newIsRootRatified", type: "bool" },
        { name: "nonce", type: "uint128" },
        { name: "deadline", type: "uint256" },
      ],
      PriceRatifierV1Offer: OFFER_TYPES.PriceRatifierV1Offer,
    }),
    message: (account, offerTree) => ({
      maker: account,
      offerTree,
      newIsRootRatified: true,
      nonce: NONCE,
      deadline: DEADLINE,
    }),
  },
  rate: {
    label: "RateRatifierV1 — SetIsRootRatified",
    verifyingContract: RATE_RATIFIER,
    offerType: "RateRatifierV1Offer",
    primaryType: "SetIsRootRatified",
    prefix: "RATE_",
    types: () => ({
      ...COMMON_TYPES,
      SetIsRootRatified: [
        { name: "maker", type: "address" },
        { name: "offerTree", type: offerTreeType("RateRatifierV1Offer", HEIGHT) },
        { name: "newIsRootRatified", type: "bool" },
        { name: "nonce", type: "uint128" },
        { name: "deadline", type: "uint256" },
      ],
      RateRatifierV1Offer: OFFER_TYPES.RateRatifierV1Offer,
    }),
    message: (account, offerTree) => ({
      maker: account,
      offerTree,
      newIsRootRatified: true,
      nonce: NONCE,
      deadline: DEADLINE,
    }),
  },
};

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

  const options = Object.entries(MODES)
    .map(([key, mode]) => `<option value="${key}">${mode.label}</option>`)
    .join("");

  app.innerHTML = `
    <p>Connected: <code>${account}</code> &middot; Chain <code>${chainId}</code></p>

    <div class="field">
      <label for="mode">What to sign <small>each option signs the same 4-offer tree, typed for its ratifier</small></label>
      <select id="mode">${options}</select>
    </div>

    <p>Verifying contract: <code id="verifying"></code> &middot; Height: <code>${HEIGHT}</code></p>

    <div class="field">
      <label for="offer">OfferTree <small>4 offers as <span id="offerTypeLabel"></span>[2][2]</small></label>
      <textarea id="offer" spellcheck="false"></textarea>
    </div>

    <button id="sign">Sign</button>
    <pre id="result"></pre>
  `;

  const modeEl = $("mode") as HTMLSelectElement;

  function refresh() {
    const mode = MODES[modeEl.value];
    $("verifying").textContent = mode.verifyingContract;
    $("offerTypeLabel").textContent = mode.offerType;
    ($("offer") as HTMLTextAreaElement).value = JSON.stringify(buildOfferTree(mode.offerType, account), null, 2);
    $("result").textContent = "";
  }

  modeEl.addEventListener("change", refresh);
  refresh();

  $("sign").addEventListener("click", async () => {
    const resultEl = $("result");
    resultEl.textContent = "Waiting for wallet…";

    try {
      const mode = MODES[modeEl.value];
      const offerTree = JSON.parse(($("offer") as HTMLTextAreaElement).value);

      const typedData = {
        types: mode.types(account),
        primaryType: mode.primaryType,
        domain: { chainId, verifyingContract: mode.verifyingContract },
        message: mode.message(account, offerTree),
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
        `uint8 constant ${mode.prefix}SIG_V = ${v};`,
        `bytes32 constant ${mode.prefix}SIG_R = ${r};`,
        `bytes32 constant ${mode.prefix}SIG_S = ${s};`,
      ].join("\n");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      resultEl.textContent = `Error: ${msg}`;
    }
  });
}

main();
