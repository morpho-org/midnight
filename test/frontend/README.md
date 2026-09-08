# Usage

Install with `cd test/frontend && npm install`.
Run with `npm run dev`.
The "Sign OfferTree" and "Sign RateOfferTree" buttons will prompt your wallet. Rate offers contain a `startRate`, `expiryRate` and `authorizedTaker` instead of `tick`.
Then you will see the offers that would be signed by signing the offer tree.
The offers are all mostly empty, except for the loan token at the top that can help distiguish them.
Then paste the output in FrontendSignatureTest.sol, and run `forge test -mc FrontendSignatureTest`