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
 * this class. */
extern int __CFConstantStringClassReference[24]
	__attribute__((alias("._OBJC_CLASS_NSCFConstantString")));
