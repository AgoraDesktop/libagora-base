/*
 * NSCFConstantString — the class a CFSTR() is.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * clang emits every CFSTR() as a static struct, and its layout is the compiler's, not a choice:
 *
 *     .quad  __CFConstantStringClassReference   # isa
 *     .long  1992                               # 0x7c8 flags
 *     .zero  4
 *     .quad  .L.str                             # the C string
 *     .quad  3                                  # its length
 *     .size  .L_unnamed_cfstring_, 32
 *
 * `{void *isa; uint32_t flags; const char *cstr; uintptr_t length}` — so the ivars below start at
 * offset 8 and land exactly on clang's fields, which is the whole of why this class is separate from
 * NSConstantString. THAT CLASS'S LAYOUT IS THE OBJECTIVE-C RUNTIME'S (libobjc2 writes its `_rflags`,
 * `_rstr`, `_rsize` when it materialises a @"..." literal) and cannot move; this one's is clang's and
 * cannot move either. Two layouts, two classes, and this is the one for the compiler's CF strings.
 *
 * WHY THERE IS AN ALIAS AT THE BOTTOM, and it is the kernel of the whole arrangement: the isa clang
 * embeds is a BARE SYMBOL, `&__CFConstantStringClassReference`, not a class symbol -- so for a CFSTR to
 * be an Objective-C object at all, that symbol's storage must BE a class. Core Foundation declares it
 * weakly (its own placeholder, for a Core Foundation with no Foundation beside it); the strong
 * definition here aliases it to this class's storage, and the same translation unit must hold both the
 * @implementation and the alias, because @c alias requires its target in the same unit.
 *
 * WHAT THIS CLASS CAN HONESTLY ANSWER. A CFSTR is ASCII by construction -- clang warns and escapes
 * anything else through MacOS Roman -- so the byte length IS the UTF-16 length and the bytes ARE UTF-8.
 * The methods below say exactly that and nothing more; a CFSTR is not a general string and does not
 * pretend to be one.
 */
#import <Foundation/Foundation.h>

@interface NSCFConstantString : NSString
{
	uint32_t _cfFlags;
	uint32_t _cfPad;	/* clang emits a 4-byte gap between the flags and the pointer */
	const char *_cfCstr;
	uintptr_t _cfLength;	/* BYTES, and for a CFSTR that is also the UTF-16 length */
}
@end

@implementation NSCFConstantString

/* AND THE TWO ENCODING DOORS CORE FOUNDATION ASKS IT FOR. CFString.c dispatches to these, and the class
 * the compiler CFSTR is did not answer them: '-[NSCFConstantString _fastestEncodingInCFStringEncoding]
 * is not implemented', raised the moment CFURL built a Core Foundation URL from a string.
 *
 * THEY ANSWER FROM THIS CLASS'S OWN STORAGE, AND THAT IS NOT A STYLE CHOICE -- ASKING CORE FOUNDATION
 * FOR THE ANSWER IS AN INFINITE RECURSION. It was written that way first: `return
 * CFStringGetFastestEncoding((CFStringRef)self)`. But that door DISPATCHES STRAIGHT BACK HERE --
 * CFStringGetFastestEncoding begins with CF_OBJC_FUNCDISPATCHV(_kCFRuntimeIDCFString, ...,
 * _fastestEncodingInCFStringEncoding), and the dispatch fires because this object's class chain reaches
 * the NSString that Foundation registered for CFString. Measured with a backtrace 523,844 frames deep,
 * alternating between the two, and it is what made CFTimeZoneCreateWithName() die for every argument:
 * Core Foundation builds its zone path through CFURL, CFURL asks a CFSTR for its encoding, and away the
 * stack went.
 *
 * AND A CFSTR IS ASCII BY CONSTRUCTION (the note at the top of this file), WHICH IS EXACTLY WHAT CORE
 * FOUNDATION ANSWERS FOR AN EIGHT-BIT STRING: both doors above return
 * __CFStringGetEightBitStringEncoding() when __CFStrIsEightBit(str), and that function is
 * kCFStringEncodingASCII in this tree. So the answer below is Core Foundation's own, without asking it. */
- (CFStringEncoding)_fastestEncodingInCFStringEncoding
{
	return kCFStringEncodingASCII;
}

- (CFStringEncoding)_smallestEncodingInCFStringEncoding
{
	return kCFStringEncodingASCII;
}

/* AND THE THIRD DOOR ON THE SAME PATH USED TO BE HERE, AND IT WAS IN THE WRONG CLASS -- MOVED TO NSString
 * (see NSCFBridging.m). It is not a constant-string question: CFStringGetCString dispatches to it for ANY
 * bridged string, and the string Core Foundation is asking about here is usually not this class at all. The
 * measurement that moved it: -_createSubstringWithRange: on a CFSTR returns a copy -- an NSOwnedString --
 * and Core Foundation's next step on that copy raised
 * '-[NSOwnedString _getCString:maxLength:encoding:] is not implemented', which in the URL parser surfaces as
 * a component answering NULL (and sometimes as a crash). The two encoding doors ABOVE stay, because they are
 * genuinely about a constant string: a CFSTR is ASCII by construction. */


/* NO DEALLOC, NO FREE: the storage is the compiler's, in the program's own data segment, and it lives
 * as long as the program does. Releasing one must therefore do nothing at all -- and -release on a
 * constant string is exactly what a caller is allowed to do after taking one. */
- (void)dealloc
{
}

- (NSUInteger)length
{
	return (NSUInteger)_cfLength;
}

- (unichar)characterAtIndex:(NSUInteger)index
{
	if (index >= (NSUInteger)_cfLength) {
		[NSException raise:NSRangeException format:@"%@: index %lu out of range (length %lu)",
			NSStringFromClass([self class]), (unsigned long)index, (unsigned long)_cfLength];
	}
	return (unichar)(unsigned char)_cfCstr[index];
}

- (const char *)UTF8String
{
	return _cfCstr == NULL ? "" : _cfCstr;
}

@end

/* THE STRONG DEFINITION OF THE BARE SYMBOL. Core Foundation declares it weakly, so this one wins at
 * load and every CFSTR() in the program -- Core Foundation's own and every caller's -- is an instance of
 * this class.
 *
 * ⚠⚠ TWO WAYS TO SAY IT, BECAUSE CLANG 23 STOPPED ACCEPTING ONE OF THEM (2026-10-21). The
 * `__attribute__((alias(...)))` form is the honest spelling and is what older compilers want — but from
 * Clang 23 a C alias may only point at a DEFINED VARIABLE OR FUNCTION, and an Objective-C class symbol is
 * neither: it is compiler-generated metadata, so the attribute is rejected with "alias must point to a
 * defined variable or function".
 *
 * The replacement is the same alias said one layer down, in the assembler, where a `.set` makes the two
 * names the same symbol without asking what KIND of thing the target is. MEASURED: on this machine's
 * clang-19 BOTH forms produce byte-identical objects — `__CFConstantStringClassReference` and
 * `._OBJC_CLASS_NSCFConstantString` at one address — so the two paths agree rather than one being a
 * guess about the other. The version test is here rather than in the build because the two spellings
 * differ by compiler, not by architecture or flag. */
#ifndef FN_CFCONSTSTRING_ELF_ALIAS
#  if defined(__clang__) && defined(__clang_major__) && __clang_major__ >= 23
#    define FN_CFCONSTSTRING_ELF_ALIAS 1
#  else
#    define FN_CFCONSTSTRING_ELF_ALIAS 0
#  endif
#endif

#if FN_CFCONSTSTRING_ELF_ALIAS
extern int __CFConstantStringClassReference[24];
/* `.globl` because a `.set` does not bind the name into the object on its own; without it the symbol
 * above would stay local and Core Foundation's weak definition would win, which is the opposite of the
 * point. The target is the class symbol clang emits for the GNUstep 2.0 ABI — note the LEADING DOT, which
 * is that ABI's spelling and not a typo. */
__asm__(".globl __CFConstantStringClassReference\n"
	".set __CFConstantStringClassReference, ._OBJC_CLASS_NSCFConstantString\n");
#else
extern int __CFConstantStringClassReference[24]
	__attribute__((alias("._OBJC_CLASS_NSCFConstantString")));
#endif
