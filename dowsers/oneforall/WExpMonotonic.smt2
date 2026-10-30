; Consecutive monotonicity of TickLib.wExp, as in dowsers/oneforall/WExpMonotonic.sol.
;
;   z3 -T:600 smt.random_seed=1 dowsers/oneforall/WExpMonotonic.smt2
;
; sat is a counterexample to wExp(x) <= wExp(x + 1). unsat is a proof over
; the mathematical integers. Division is toward zero, matching Solidity.
; The shift is expR * 2^q. The requires are the casts the Solidity model
; checks: q fits a uint256 shift and expR is non-negative, and a negative
; input does not divide by zero.
;
; Constants are the WAD literals in src/libraries/TickLib.sol.
; MAX_INPUT = floor(ln(1.005) * 1e18) * (MAX_TICK / 2).

(set-option :produce-models true)
(set-option :timeout 600000)
(set-logic QF_NIA)

(define-fun ln2 () Int 693147180559945309)
(define-fun offset () Int 322611214989459870)
(define-fun max_input () Int 16817989975223754156)
(define-fun e18 () Int 1000000000000000000)
(define-fun e36 () Int 1000000000000000000000000000000000000)
(define-fun two_e18 () Int 2000000000000000000)
(define-fun three_e18 () Int 3000000000000000000)

; Toward-zero division. d is positive. Z3's div rounds toward -infinity.
(define-fun div0 ((n Int) (d Int)) Int
  (ite (>= n 0) (div n d) (- (div (- n) d))))

; 2^q for 0 <= q < 256.
(define-fun pow2 ((q Int)) Int
  (* (ite (= (mod q 2) 1) 2 1)
     (ite (= (mod (div q 2) 2) 1) 4 1)
     (ite (= (mod (div q 4) 2) 1) 16 1)
     (ite (= (mod (div q 8) 2) 1) 256 1)
     (ite (= (mod (div q 16) 2) 1) 65536 1)
     (ite (= (mod (div q 32) 2) 1) 4294967296 1)
     (ite (= (mod (div q 64) 2) 1) 18446744073709551616 1)
     (ite (= (mod (div q 128) 2) 1) 340282366920938463463374607431768211456 1)))

(define-fun q_of ((y Int)) Int (div0 (+ y offset) ln2))
(define-fun r_of ((y Int)) Int (- y (* (q_of y) ln2)))
(define-fun second_of ((y Int)) Int (div0 (* (r_of y) (r_of y)) two_e18))
(define-fun third_of ((y Int)) Int (div0 (* (second_of y) (r_of y)) three_e18))
(define-fun expR_of ((y Int)) Int (+ e18 (r_of y) (second_of y) (third_of y)))
(define-fun positive ((y Int)) Int (* (expR_of y) (pow2 (q_of y))))

(define-fun wexp ((x Int)) Int
  (ite (< x 0) (div0 e36 (positive (- x))) (positive x)))

; The non-negative argument each call evaluates.
(define-fun arg ((x Int)) Int (ite (< x 0) (- x) x))

(declare-const x Int)
(declare-const next Int)
(assert (= next (+ x 1)))
(assert (<= (- max_input) x))
(assert (< x max_input))

; Both calls pass the range requires. A negative call also has a positive divisor.
(assert (and (>= (q_of (arg x)) 0) (< (q_of (arg x)) 256) (>= (expR_of (arg x)) 0)))
(assert (and (>= (q_of (arg next)) 0) (< (q_of (arg next)) 256) (>= (expR_of (arg next)) 0)))
(assert (=> (< x 0) (> (positive (arg x)) 0)))
(assert (=> (< next 0) (> (positive (arg next)) 0)))

; Counterexample to the consecutive step.
(assert (> (wexp x) (wexp next)))

(check-sat)
(get-value (x next (wexp x) (wexp next) (q_of (arg x)) (q_of (arg next)) (expR_of (arg x)) (expR_of (arg next))))
