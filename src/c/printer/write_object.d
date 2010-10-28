/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    write_object.d -- basic printer routine.
*/
/*
    Copyright (c) 1984, Taiichi Yuasa and Masami Hagiya.
    Copyright (c) 1990, Giuseppe Attardi.
    Copyright (c) 2001, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <ecl/ecl.h>
#include <ecl/internal.h>
#include <ecl/bytecodes.h>

bool
_ecl_will_print_as_hash(cl_object x)
{
	cl_object circle_counter = ecl_symbol_value(@'si::*circle-counter*');
	cl_object circle_stack = ecl_symbol_value(@'si::*circle-stack*');
	cl_object code = ecl_gethash_safe(x, circle_stack, OBJNULL);
	if (FIXNUMP(circle_counter)) {
		return !(code == OBJNULL || code == Cnil);
	} else if (code == OBJNULL) {
		/* Was not found before */
		_ecl_sethash(x, circle_stack, Cnil);
		return 0;
	} else {
		return 1;
	}
}

/* To print circular structures, we traverse the structure by adding
   a pair <element, flag> to the interpreter stack for each element visited.
   flag is initially NIL and becomes T if the element is visited again.
   After the visit we squeeze out all the non circular elements.
   The flags is used during printing to distinguish between the first visit
   to the element.
 */

static cl_fixnum
search_print_circle(cl_object x)
{
	cl_object circle_counter = ecl_symbol_value(@'si::*circle-counter*');
	cl_object circle_stack = ecl_symbol_value(@'si::*circle-stack*');
	cl_object code;

	if (!FIXNUMP(circle_counter)) {
		code = ecl_gethash_safe(x, circle_stack, OBJNULL);
		if (code == OBJNULL) {
			/* Was not found before */
			_ecl_sethash(x, circle_stack, Cnil);
			return 0;
		} else if (code == Cnil) {
			/* This object is referenced twice */
			_ecl_sethash(x, circle_stack, Ct);
			return 1;
		} else {
			return 2;
		}
	} else {
		code = ecl_gethash_safe(x, circle_stack, OBJNULL);
		if (code == OBJNULL || code == Cnil) {
			/* Is not referenced or was not found before */
			/* _ecl_sethash(x, circle_stack, Cnil); */
			return 0;
		} else if (code == Ct) {
			/* This object is referenced twice, but has no code yet */
			cl_fixnum new_code = fix(circle_counter) + 1;
			circle_counter = MAKE_FIXNUM(new_code);
			_ecl_sethash(x, circle_stack, circle_counter);
			ECL_SETQ(ecl_process_env(), @'si::*circle-counter*',
				 circle_counter);
			return -new_code;
		} else {
			return fix(code);
		}
	}
}

cl_object
si_write_object(cl_object x, cl_object stream)
{
	bool circle;
	if (ecl_symbol_value(@'*print-pretty*') != Cnil) {
		cl_object f = funcall(2, @'pprint-dispatch', x);
		if (VALUES(1) != Cnil) {
			funcall(3, f, stream, x);
			return x;
		}
	}
	circle = ecl_print_circle();
	if (circle && !Null(x) && !FIXNUMP(x) && !CHARACTERP(x) &&
	    (LISTP(x) || (x->d.t != t_symbol) || (Null(x->symbol.hpack))))
	{
		cl_object circle_counter;
		cl_fixnum code;
		circle_counter = ecl_symbol_value(@'si::*circle-counter*');
		if (circle_counter == Cnil) {
			cl_env_ptr env = ecl_process_env();
			cl_object hash =
				cl__make_hash_table(@'eq',
						    MAKE_FIXNUM(1024),
                                                    cl_core.rehash_size,
                                                    cl_core.rehash_threshold, Cnil);
			ecl_bds_bind(env, @'si::*circle-counter*', Ct);
			ecl_bds_bind(env, @'si::*circle-stack*', hash);
			si_write_object(x, cl_core.null_stream);
			ECL_SETQ(env, @'si::*circle-counter*', MAKE_FIXNUM(0));
			si_write_object(x, stream);
			cl_clrhash(hash);
			ecl_bds_unwind_n(env, 2);
			return x;
		}
		code = search_print_circle(x);
		if (!FIXNUMP(circle_counter)) {
			/* We are only inspecting the object to be printed. */
			/* Only run X if it was not referenced before */
			if (code != 0) return x;
		} else if (code == 0) {
			/* Object is not referenced twice */
		} else if (code < 0) {
			/* Object is referenced twice. We print its definition */
			ecl_write_char('#', stream);
			_ecl_write_fixnum(-code, stream);
			ecl_write_char('=', stream);
		} else {
			/* Second reference to the object */
			ecl_write_char('#', stream);
			_ecl_write_fixnum(code, stream);
			ecl_write_char('#', stream);
			return x;
		}
	}
	return si_write_ugly_object(x, stream);
}