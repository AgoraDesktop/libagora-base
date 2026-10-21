/*
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 */
/*
 * NSInvocation_arm64.S — the two things the AAPCS64 needs and C cannot say: capturing the
 * register file of a call that is being forwarded, and issuing a call from a stored register
 * file. The AArch64 counterpart of NSInvocation_amd64.S; the image layout is the SAME and is
 * the contract with Foundation/NSInvocation.h, which is where FN_GPR and friends are
 * documented as a pair with `fn_regs_t`.
 *
 * WHY NOT C, AND WHY THIS IS SHORTER THAN THE x86-64 FILE. On x86-64 the capture needs
 * assembler because a variadic callee saves the SSE registers only when the caller's `al`
 * says they are used, and `al` is undefined for a non-variadic prototype. AArch64 has no
 * such register: a variadic callee spills x0-x7 and v0-v7 unconditionally, because it can
 * see from its own definition that it is variadic. Neither language feature helps a
 * FORWARDED method, though — its prototype is whatever the method's signature says, which is
 * non-variadic and fixed — so the capture is still hand-written. What AArch64 buys is a fixed
 * caller/callee contract to write against instead of a per-call flag to reason about: the
 * argument registers are x0-x7 and v0-v7, the return registers are x0 and v0, and the
 * incoming stack arguments begin at sp.
 *
 * ⚠ THE IMAGE KEEPS SIX INTEGER SLOTS, AND THAT IS THE DOCUMENTED SUBSET RATHER THAN A LIMIT
 * OF THIS ARCHITECTURE. AArch64 passes eight integer arguments to x0-x7; `fn_regs_t` has
 * `gpr[6]`, and NSInvocation.m refuses an argument that needs a seventh (fn_place, "gpr >= 6")
 * — the SAME refusal it makes on x86-64, which also passes six. So a signature marshals or
 * refuses identically on both, and a caller written against one is correct on the other. The
 * two registers this file does not keep (x6, x7) are unreachable, not truncated: nothing can
 * be placed there.
 *
 * AND WHY EVERY FUNCTION CARRIES ITS OWN `.cfi_*` DIRECTIVES: the same lesson the x86-64 file
 * records from §62.22, MEASURED there and structural here. A hand-written frame with no DWARF
 * has no FDE, the unwinder cannot walk through it, and an exception raised by a method called
 * through either trampoline therefore aborts the process with no `@try` above it able to
 * catch. On AArch64 the return address lives in x30, so a trampoline that overwrites it with
 * `bl` and keeps no frame is UNWALKABLE BY CONSTRUCTION — the standard `stp x29, x30` prologue
 * below is what makes the return address recoverable, and the `.cfi_*` directives are what
 * tell the unwinder the frame has that shape.
 */

#define FN_GPR		0
#define FN_SSE		48
#define FN_STACK	176
#define FN_RET_INT	184
#define FN_RET_FP	192
#define FN_SSE_COUNT	200

	.text

/*
 * The IMP __objc_msg_forward2 answers with, so the RUNTIME calls it with the forwarded
 * method's own arguments — which is where they are captured. It fills fn_forward_regs, calls
 * the C handler (which copies the image out, builds the invocation and delivers it), then
 * returns whatever the handler left in the image's return slots.
 *
 * The image address is computed TWICE — before the stores and again before the loads —
 * because x9 is caller-saved and the handler is free to clobber it. Recomputing two
 * instructions is cheaper than parking the address in a callee-saved register and saving that
 * register around the call.
 */
	.globl	fn_forward_entry
	.hidden	fn_forward_entry	/* one shared object, so bind it HERE: that is what
					 * makes the PC-relative access to the image
					 * below legal, with or without -fPIC */
	.type	fn_forward_entry, @function
fn_forward_entry:
	.cfi_startproc
	stp	x29, x30, [sp, #-16]!
	.cfi_def_cfa_offset	16
	.cfi_offset	x29, -16
	.cfi_offset	x30, -8
	mov	x29, sp
	.cfi_def_cfa_register	x29

	adrp	x9, fn_forward_regs
	add	x9, x9, :lo12:fn_forward_regs
	stp	x0, x1, [x9, #FN_GPR+0]
	stp	x2, x3, [x9, #FN_GPR+16]
	stp	x4, x5, [x9, #FN_GPR+32]
	/* v0-v7 are 128 bits each and `fn_regs_t.sse` gives each one 16 bytes, so the whole
	 * register goes in with a store-pair and no narrowing: a float in s0 and a double in d0
	 * are the low bits of q0, and the C half copies out exactly the bytes the argument's
	 * size asks for (fnStoreReturnIntoImage's mirror image). */
	stp	q0, q1, [x9, #FN_SSE+0]
	stp	q2, q3, [x9, #FN_SSE+32]
	stp	q4, q5, [x9, #FN_SSE+64]
	stp	q6, q7, [x9, #FN_SSE+96]

	/* THE STACK ARGUMENTS, as an ADDRESS rather than a copy — the same thing the x86-64
	 * `leaq 16(%rbp)` stores. AArch64 puts stacked arguments at sp on entry, and this frame
	 * has already moved sp down by 16, so the caller's sp is sp+16 and that is the first
	 * stacked word. (The image keeps the pointer for completeness; NSInvocation refuses any
	 * signature that would need to read through it.) */
	add	x10, sp, #16
	str	x10, [x9, #FN_STACK]

	bl	fn_forward_handler

	adrp	x9, fn_forward_regs
	add	x9, x9, :lo12:fn_forward_regs
	ldr	x0, [x9, #FN_RET_INT]
	ldr	d0, [x9, #FN_RET_FP]

	ldp	x29, x30, [sp], #16
	.cfi_def_cfa	sp, 0
	.cfi_restore	x29
	.cfi_restore	x30
	ret
	.cfi_endproc
	.size	fn_forward_entry, .-fn_forward_entry

/*
 * void fn_call_image(IMP function, fn_regs_t *regs);
 *
 * The inverse: load the register file from `regs`, call `function`, and store the result back
 * into `regs`. STACK arguments are deliberately NOT placed — v1 supports register-only
 * signatures, and NSInvocation refuses the rest loudly.
 *
 * Unlike the x86-64 version there is NO argument-count register to set before the call:
 * AArch64 has no `al`, and a variadic callee spills everything because it knows it is
 * variadic. `sse_count` is therefore read by nothing here; it stays in the image because the
 * struct is shared with the architecture that needs it.
 *
 * The function and the image are parked in CALLEE-SAVED registers (x19, x20) rather than
 * stack slots, because both must survive the call and a callee is obliged to preserve those —
 * which is also why they are saved in the prologue and restored in the epilogue, before the
 * frame is popped.
 */
	.globl	fn_call_image
	.hidden	fn_call_image
	.type	fn_call_image, @function
fn_call_image:
	.cfi_startproc
	stp	x29, x30, [sp, #-32]!
	.cfi_def_cfa_offset	32
	.cfi_offset	x29, -32
	.cfi_offset	x30, -24
	stp	x19, x20, [sp, #16]
	.cfi_offset	x19, -16
	.cfi_offset	x20, -8
	mov	x29, sp
	.cfi_def_cfa_register	x29

	mov	x19, x0			/* the function to call */
	mov	x20, x1			/* the image, parked across the call */

	ldp	x0, x1, [x20, #FN_GPR+0]
	ldp	x2, x3, [x20, #FN_GPR+16]
	ldp	x4, x5, [x20, #FN_GPR+32]
	ldp	q0, q1, [x20, #FN_SSE+0]
	ldp	q2, q3, [x20, #FN_SSE+32]
	ldp	q4, q5, [x20, #FN_SSE+64]
	ldp	q6, q7, [x20, #FN_SSE+96]

	blr	x19

	/* THE RESULT IN THE IMAGE, x0 for integers and d0 for floating point — the same two
	 * slots the x86-64 file writes from rax and xmm0. A float return is the low 32 bits of
	 * d0 and the C half copies out the four bytes the signature asks for. */
	str	x0, [x20, #FN_RET_INT]
	str	d0, [x20, #FN_RET_FP]

	ldp	x19, x20, [sp, #16]
	.cfi_restore	x19
	.cfi_restore	x20
	ldp	x29, x30, [sp], #32
	.cfi_def_cfa	sp, 0
	.cfi_restore	x29
	.cfi_restore	x30
	ret
	.cfi_endproc
	.size	fn_call_image, .-fn_call_image

	.data
	/* `.balign` RATHER THAN `.align`: on AArch64 `.align 16` means 2^16, which would pad the
	 * object by up to 64 KiB for an alignment nothing needs. `.balign` takes bytes on every
	 * target. Sixteen is what the x86-64 image asks for and what a store-pair of q registers
	 * wants. */
	.balign	16
	.globl	fn_forward_regs
	.hidden	fn_forward_regs
	.type	fn_forward_regs, @object
	.size	fn_forward_regs, 224
fn_forward_regs:
	.zero	224
