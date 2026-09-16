# Usage

Install with `cd test/frontend && npm install`.
Run with `npm run dev`.
Select the offer to sign and then the "Sign" button will prompt your wallet. There are three options, all signing the same
tree of four offers, each typed for the ratifier that verifies it:

- `EcrecoverRatifier — OfferTree`: the `OfferTree` signed by the maker, checked in `isRatified`.
- `PriceRatifierV1 — SetIsRootRatified`: the ratification of a tree of `PriceRatifierV1Offer` (the offer with an
  added `allowedTaker`), checked in `setIsRootRatifiedWithSig`.
- `RateRatifierV1 — SetIsRootRatified`: same, for a tree of `RateRatifierV1Offer` (`tick` replaced by `rate`).

Then you will see the offers that would be signed by signing the offer tree.
The offers are all mostly empty, except for the loan token at the top that can help distinguish them.
Then paste the output in FrontendSignatureTest.sol for the offer type signed and run
`forge test -mc FrontendSignatureTest`
