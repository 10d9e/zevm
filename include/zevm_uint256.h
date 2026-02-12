#ifndef ZEVM_UINT256_H
#define ZEVM_UINT256_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * ZEVM uint256 FFI — high-performance EVM arithmetic for Java/Panama.
 *
 * Layout: each U256 operand is 4 consecutive uint64_t in little-endian limb order.
 *   buf[0..3] = operand a  (limbs[0] is least significant)
 *   buf[4..7] = operand b
 *   buf[8..11] = operand c  (for addmod/mulmod only)
 *
 * Mutating operations write the result back to buf[0..3].
 */

/* Arithmetic (result in buf[0..3]) */
void uint256_add(uint64_t *buf);
void uint256_sub(uint64_t *buf);
void uint256_mul(uint64_t *buf);
void uint256_div(uint64_t *buf);
void uint256_mod(uint64_t *buf);
void uint256_sdiv(uint64_t *buf);
void uint256_smod(uint64_t *buf);
void uint256_addmod(uint64_t *buf);   /* 3 operands: a, b, n */
void uint256_mulmod(uint64_t *buf);   /* 3 operands: a, b, n */
void uint256_exp(uint64_t *buf);
void uint256_signextend(uint64_t *buf);

/* Bitwise (result in buf[0..3]) */
void uint256_and(uint64_t *buf);
void uint256_or(uint64_t *buf);
void uint256_xor(uint64_t *buf);
void uint256_not(uint64_t *buf);      /* 1 operand */
void uint256_byte(uint64_t *buf);
void uint256_shl(uint64_t *buf);
void uint256_shr(uint64_t *buf);
void uint256_sar(uint64_t *buf);

/* Comparison (returns 0 or 1) */
uint64_t uint256_lt(const uint64_t *buf);
uint64_t uint256_gt(const uint64_t *buf);
uint64_t uint256_slt(const uint64_t *buf);
uint64_t uint256_sgt(const uint64_t *buf);
uint64_t uint256_eq(const uint64_t *buf);
uint64_t uint256_iszero(const uint64_t *buf);  /* 1 operand */

#ifdef __cplusplus
}
#endif

#endif /* ZEVM_UINT256_H */
