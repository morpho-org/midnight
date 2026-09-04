# Usage

Install with `cd test/frontend && npm install`.
Run with `npm run dev`.

## EcrecoverRatifier (sign-root.ts)

The "Sign OfferTree" button will prompt your wallet.
Then you will see the offers that would be signed by signing the offer tree.
The offers are all mostly empty, except for the loan token at the top that can help distiguish them.
Then paste the output in FrontendSignatureTest.sol, and run `forge test -mc FrontendSignatureTest`

## EcrecoverRateRatifier (sign-rate-root.ts)

Update `index.html` to point to `sign-rate-root.ts` instead of `sign-root.ts`, then run `npm run dev`.
The "Sign RateOfferTree" button will prompt your wallet to sign a tree of rate offers (with `startRate`/`expiryRate` instead of `tick`).
Then paste the output in FrontendSignatureTest.sol, and run `forge test -mc FrontendRateSignatureTest`
