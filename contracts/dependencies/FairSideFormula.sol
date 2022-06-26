// SPDX-License-Identifier: Unlicense

pragma solidity =0.6.8;

import "./ABDKMathQuad.sol";

// solhint-disable not-rely-on-time, var-name-mixedcase, reason-string /*
library FairSideFormula {
    using ABDKMathQuad for bytes16;

    // A constant (adjusted before launch, in precalculated values below assumed to be 0.00006)
    bytes16 private constant A = 0x3ff0f75104d551d68c692f6e82949a56;
    // C constant (adjusted before launch, in precalculated values below assumed to be 55,000,000)
    bytes16 private constant C = 0x4018a39de00000000000000000000000;
    // π / 4
    bytes16 private constant PI_4 = 0x3ffe921fb78121fb78121fb78121fb78;
    // π / 2
    bytes16 private constant PI_2 = 0x3fff921fb78121fb78121fb78121fb78;
    // 0.2447: constant in the approximation of arctan
    bytes16 private constant APPROX_A = 0x3ffcf525460aa64c2f837b4a2339c0eb;
    // 0.0663: constant in the approximation of arctan
    bytes16 private constant APPROX_B = 0x3ffb0f9096bb98c7e28240b780346dc5;
    // 1: in quadruple precision form
    bytes16 private constant ONE = 0x3fff0000000000000000000000000000;
    // 2: in quadruple precision form
    bytes16 private constant TWO = 0x40000000000000000000000000000000;
    // 975.61: older outer constant (I couldn't reverse engineer the exact formula)
    // 22330.695286005: new outer constant from formula C^(1/4)/(4*sqrt(2)*A^(3/4))  // 22330.695286005448
    bytes16 private constant MULTIPLIER_FULL =
        0x400d5ceac7f90df35db03465b840a3b4;
    /* // 3.06356:
    bytes16 private constant MULTIPLIER_ARCTAN =
        0x40008822bbecaab8a5ce5b4245f5ad96; */
    // In the new implementation this becomes 2
    bytes16 private constant MULTIPLIER_ARCTAN =
        0x40000000000000000000000000000000;
    /* // 1.53178
    bytes16 private constant MULTIPLIER_LOG =
        0x3fff8822bbecaab8a5ce5b4245f5ad96; */
    // In the new implementation this becomes 1
    bytes16 private constant MULTIPLIER_LOG =
        0x3fff0000000000000000000000000000;
    // formula of MULTIPLIER_INNER_ARCTAN is (sqrt(2)/(AC)**(1/4))
    // 0.163209: old value for A = 0.001025 and C = 5,500,000
    // 0.186589: new value for A = 0.00006 and C = 55,000,000
    /* bytes16 private constant MULTIPLIER_INNER_ARCTAN =
        0x3ffc4e40852b4d8ba40d90e23af31b15; */
    // old value
    bytes16 private constant MULTIPLIER_INNER_ARCTAN =
        0x3ffc7e225fa658c4bd33d29563a9f383; // new value
    // formula of MULTIPLIER_INNER_LOG_A is sqrt(A*C)
    // 75.0833: old value for A = 0.001025 and C = 5,500,000
    // 57.4456: new value for A = 0.00006 and C = 55,000,000
    /* bytes16 private constant MULTIPLIER_INNER_LOG_A =
        0x40052c554c985f06f694467381d7dbf4; */
    // old value
    bytes16 private constant MULTIPLIER_INNER_LOG_A =
        0x4004cb9096bb98c7e28240b780346dc5; // new value
    // formula of MULTIPLIER_INNER_LOG_B is sqrt(2) * (A*C)^(1/4)
    // 12.2542: old value for A = 0.001025 and C = 5,500,000
    // 10.7187: new value for A = 0.00006 and C = 55,000,000
    /* bytes16 private constant MULTIPLIER_INNER_LOG_B =
        0x400288226809d495182a9930be0ded28; */
    // old value
    bytes16 private constant MULTIPLIER_INNER_LOG_B =
        0x400256ff972474538ef34d6a161e4f76;
    // 10e18
    bytes16 private constant NORMALIZER = 0x403abc16d674ec800000000000000000;

    // 0.0776509570923569
    bytes16 private constant ARCTAN_2_A = 0x3ffb3e0eee136fb4e88c3b51afdd813b;
    // 0.287434475393028
    bytes16 private constant ARCTAN_2_B = 0x3ffd2655391e3950b9c4210dcff7e0e5;
    // 0.6399276529
    bytes16 private constant ARCTAN_3_A = 0x3ffe47a498ea05e88353e06682770573;

    // calculate arctan (only good between [-1,1]) using approximation
    // (a*x + x^2 + x^3) / (1 + (a+1)*x + (a+1)*x^2 + x^3 )
    // for a = 0.6399276529
    function _arctan(bytes16 x) private pure returns (bytes16) {
        bytes16 x_2 = x.mul(x);
        bytes16 x_3 = x_2.mul(x);
        bytes16 a_plus_1 = ARCTAN_3_A.add(ONE);
        bytes16 a_plus_1_x = a_plus_1.mul(x);
        bytes16 nominator = ARCTAN_3_A.mul(x).add(x_2).add(x_3);
        bytes16 denominator = ONE.add(a_plus_1_x).add(a_plus_1.mul(x_2)).add(
            x_3
        );
        return PI_2.mul(nominator).div(denominator);
    }

    // extends aproximation to the whole range of real numbers
    function arctan(bytes16 x) public pure returns (bytes16 arc) {
        // Tautology:
        // - arctan(x) = π / 2 - arctan(1 / x), x > 0
        // - arctan(x) = - π / 2 - arctan(1 / x), x < 0
        if (x.cmp(ONE) != int8(1) && x.cmp(ONE.neg()) != int256(-1)) {
            arc = _arctan(x);
        } else {
            arc = (x.sign() == -1 ? PI_2.neg() : PI_2).sub(_arctan(ONE.div(x)));
        }
    }

    function _arctan2(bytes16 a) private pure returns (bytes16) {
        return
            a.mul(PI_4).sub(
                a.mul(a.abs().sub(ONE)).mul(APPROX_A.add(APPROX_B.mul(a.abs())))
            );
    }

    function arctan2(bytes16 x) public pure returns (bytes16 arc) {
        // Tautology:
        // - arctan(x) = π / 2 - arctan(1 / x), x > 0
        // - arctan(x) = - π / 2 - arctan(1 / x), x < 0
        if (x.cmp(ONE) != int8(1) && x.cmp(ONE.neg()) != int256(-1)) {
            arc = _arctan2(x);
        } else {
            arc = (x.sign() == -1 ? PI_2.neg() : PI_2).sub(
                _arctan2(ONE.div(x))
            );
        }
    }

    function _pow3(bytes16 x) private pure returns (bytes16) {
        return x.mul(x).mul(x);
    }

    // Calculates (4√x)^3 and (√x)^3
    function rootPows(bytes16 x) private pure returns (bytes16, bytes16) {
        bytes16 x3_2 = x.mul(x.sqrt());
        bytes16 x3_4 = x3_2.sqrt();
        return (x3_4, x3_2);
    }

    // For x <= 3811 use first arctan approximation
    // For x > 3811 use the second one
    // If the result is negative we need to add PI because of a special property in the formula of arctan addition
    function arcsMix(bytes16 x, bytes16 fS3_4) private pure returns (bytes16) {
        bytes16 arcInner = MULTIPLIER_INNER_ARCTAN.mul(x).div(fS3_4);
        bytes16 arcA;
        if (x.cmp(ABDKMathQuad.fromUInt(3811)) != int256(1)) {
            arcA = arctan(
                TWO.mul(arcInner).div(TWO.sub(arcInner.mul(arcInner)))
            );
        } else {
            arcA = arctan2(
                TWO.mul(arcInner).div(TWO.sub(arcInner.mul(arcInner)))
            );
        }
        if (uint128(arcA) >= 0x80000000000000000000000000000000) {
            arcA = arcA.add(PI_2.mul(TWO));
        }
        return arcA;
    }

    // Calculates ln terms (positive, negative)
    function lns(
        bytes16 x,
        bytes16 fS3_4,
        bytes16 fS3_2
    ) private pure returns (bytes16, bytes16) {
        bytes16 a = MULTIPLIER_INNER_LOG_A.mul(fS3_2);
        bytes16 b = x.mul(x);
        a = a.add(b);
        b = MULTIPLIER_INNER_LOG_B.mul(fS3_4).mul(x);
        return (a.add(b).abs().ln(), a.sub(b).abs().ln());
    }

    /**
     * For a = 0.001025 and c = 5500000:
     *
     * 975.61 * fS^(3/4) * (
     *      -3.06356 * arctan(
     *          1 - (
     *              (0.163209 * x) / fS^(3/4)
     *          )
     *      )
     *      +3.06356 * arctan(
     *          1 + (
     *              (0.163209 * x) / fS^(3/4)
     *          )
     *      )
     *      -1.53178 * log(
     *          75.0833 * fS^(3/2) - 12.2542 * fS^(3/4) * x + x^2)
     *      )
     *      +1.53178 * log(
     *          75.0833 * fS^(3/2) + 12.2542 * fS^(3/4) * x + x^2)
     *      )
     *  )
     */
    // this is old formula
    function _g(bytes16 x, bytes16 fShare) private pure returns (bytes16) {
        // A is 3/4 and B is 3/2
        (bytes16 fShareA, bytes16 fShareB) = rootPows(fShare);
        bytes16 multiplier = fShareA.mul(MULTIPLIER_FULL);
        // (positive, negative)
        bytes16 arcA = arcsMix(x, fShareA);
        // (positive, negative)
        (bytes16 lnA, bytes16 lnB) = lns(x, fShareA, fShareB);

        bytes16 result = multiplier.mul(
            arcA.mul(MULTIPLIER_ARCTAN).add(lnA.mul(MULTIPLIER_LOG)).sub(
                lnB.mul(MULTIPLIER_LOG)
            )
        );
        return result;
    }

    function _normalize(bytes16 x) public pure returns (uint256) {
        return x.mul(NORMALIZER).toUInt();
    }

    function _denormalize(uint256 a) public pure returns (bytes16) {
        return ABDKMathQuad.fromUInt(a).div(NORMALIZER);
    }

    // g represents the relation between capital and token supply (integral of 1 / f(x))
    function g(uint256 x, uint256 fShare) public pure returns (uint256) {
        bytes16 _x = _denormalize(x);
        bytes16 _fShare = _denormalize(fShare);
        return _normalize(_g(_x, _fShare));
    }

    // f(x) = A + (fShare / C) * (x / fShare)^4
    function _f(bytes16 x, bytes16 fShare) private pure returns (bytes16) {
        return A.add(_pow3(x).mul(x).div(_pow3(fShare).mul(C)));
    }

    // f represents the relation between capital and token price
    function f(uint256 x, uint256 fShare) public pure returns (uint256) {
        bytes16 _x = _denormalize(x);
        bytes16 _fShare = _denormalize(fShare);
        return _normalize(_f(_x, _fShare));
    }

    // C = initial minted amount of tokens
    // fShare = minimal capital requirement

    // beginning
    // A = 0.001025
    // C = 5500000

    // current desired constants
    // A = 0.00006 -> 0.00008
    // C = 55000000

    // function tests(uint256 x, uint256 fShare) public pure returns (int256,int256,int256,int256) {
    //     bytes16 _x = ABDKMathQuad.fromUInt(x);
    //     bytes16 _fShare = ABDKMathQuad.fromUInt(fShare);
    //     // A is 3/4 and B is 3/2
    //     (bytes16 fShareA, bytes16 fShareB) = rootPows(_fShare);
    //     // (0.163209 * x) / fS^(3/4)
    //     bytes16 innerArc = MULTIPLIER_INNER_ARCTAN.mul(_x).div(fShareA);
    //     // 1 - innerArc
    //     bytes16 innerFirst = ONE.sub(innerArc);
    //     // 1 + innerArc
    //     bytes16 innerSecond = ONE.add(innerArc);
    //     return (_normalize(arctan(innerFirst)), arctan(innerFirst).toInt(),_normalize(arctan(innerSecond)), arctan(innerSecond).toInt());
    // }
}
