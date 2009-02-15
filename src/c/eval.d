/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    eval.c -- Eval.
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
#include <ecl/ecl-inl.h>

cl_object *
_ecl_va_sp(cl_narg narg)
{
	return ecl_process_env()->stack_top - narg;
}

static cl_object
build_funcall_frame(cl_object f, cl_va_list args)
{
	cl_env_ptr env = ecl_process_env();
	cl_index n = args[0].narg;
	cl_object *p = args[0].sp;
	f->frame.stack = 0;
	if (!p) {
#ifdef ECL_USE_VARARG_AS_POINTER
		p = (cl_object*)(args[0].args);
#else
		cl_index i;
		p = env->values;
		for (i = 0; i < n; i++) {
			p[i] = va_arg(args[0].args, cl_object);
		}
		f->frame.stack = (void*)0x1;
#endif
	}
	f->frame.bottom = p;
	f->frame.top = p + n;
	f->frame.t = t_frame;
	f->frame.env = env;
	return f;
}

/* Calling conventions:
   Compiled C code calls lisp function supplying #args, and args.
   Linking function performs check_args, gets jmp_buf with _setjmp, then
    if cfun then stores C code address into function link location
	    and transfers to jmp_buf at cf_self
    if cclosure then replaces #args with cc_env and calls cc_self
    otherwise, it emulates funcall.
 */

cl_object
ecl_apply_from_stack_frame(cl_env_ptr env, cl_object frame, cl_object x)
{
	cl_object *sp = frame->frame.bottom;
	cl_index narg = frame->frame.top - sp;
	cl_object fun = x;
      AGAIN:
	if (fun == OBJNULL || fun == Cnil)
		FEundefined_function(x);
	switch (type_of(fun)) {
	case t_cfunfixed:
		env->function = fun;
		if (narg != (cl_index)fun->cfun.narg)
			FEwrong_num_arguments(fun);
		return APPLY_fixed(narg, fun->cfunfixed.entry_fixed, sp);
	case t_cfun:
		env->function = fun;
		return APPLY(narg, fun->cfun.entry, sp);
	case t_cclosure:
		env->function = fun;
		return APPLY(narg, fun->cclosure.entry, sp);
#ifdef CLOS
	case t_instance:
		switch (fun->instance.isgf) {
		case ECL_STANDARD_DISPATCH:
			env->function = fun;
			return _ecl_standard_dispatch(env, frame, fun);
		case ECL_USER_DISPATCH:
			fun = fun->instance.slots[fun->instance.length - 1];
		default:
			FEinvalid_function(fun);
		}
		goto AGAIN;
#endif
	case t_symbol:
		if (fun->symbol.stype & stp_macro)
			FEundefined_function(x);
		fun = SYM_FUN(fun);
		goto AGAIN;
	case t_bytecodes:
		return ecl_interpret(frame, Cnil, fun, 0);
	case t_bclosure:
		return ecl_interpret(frame, fun->bclosure.lex, fun->bclosure.code, 0);
	default:
	ERROR:
		FEinvalid_function(x);
	}
}

cl_objectfn
ecl_function_dispatch(cl_env_ptr env, cl_object x)
{
	cl_object fun = x;
      AGAIN:
	if (fun == OBJNULL || fun == Cnil)
		FEundefined_function(x);
	switch (type_of(fun)) {
	case t_cfunfixed:
		env->function = fun;
		return fun->cfunfixed.entry;
	case t_cfun:
		env->function = fun;
		return fun->cfun.entry;
	case t_cclosure:
		env->function = fun;
		return fun->cclosure.entry;
#ifdef CLOS
	case t_instance:
                env->function = fun;
                return fun->instance.entry;
#endif
	case t_symbol:
		if (fun->symbol.stype & stp_macro)
			FEundefined_function(x);
		fun = SYM_FUN(fun);
		goto AGAIN;
	case t_bytecodes:
		env->function = fun;
                return fun->bytecodes.entry;
	case t_bclosure:
		env->function = fun;
                return fun->bclosure.entry;
	default:
	ERROR:
		FEinvalid_function(x);
	}
}

@(defun funcall (function &rest funargs)
	struct ecl_stack_frame frame_aux;
@
	return ecl_apply_from_stack_frame(the_env, build_funcall_frame((cl_object)&frame_aux, funargs), function);
@)

@(defun apply (fun lastarg &rest args)
@
	if (narg == 2 && type_of(lastarg) == t_frame) {
		return ecl_apply_from_stack_frame(the_env, lastarg, fun);
	} else {
		cl_object out;
		cl_index i;
		struct ecl_stack_frame frame_aux;
		const cl_object frame = ecl_stack_frame_open(the_env,
							     (cl_object)&frame_aux,
							     narg -= 2);
		for (i = 0; i < narg; i++) {
			ecl_stack_frame_elt_set(frame, i, lastarg);
			lastarg = cl_va_arg(args);
		}
		if (type_of(lastarg) == t_frame) {
			/* This could be replaced with a memcpy() */
			cl_object *p = lastarg->frame.bottom;
			while (p != lastarg->frame.top) {
				ecl_stack_frame_push(frame, *(p++));
			}
		} else loop_for_in (lastarg) {
			if (i >= CALL_ARGUMENTS_LIMIT) {
				ecl_stack_frame_close(frame);
				FEprogram_error("CALL-ARGUMENTS-LIMIT exceeded",0);
			}
			ecl_stack_frame_push(frame, CAR(lastarg));
			i++;
		} end_loop_for_in;
		out = ecl_apply_from_stack_frame(the_env, frame, fun);
		ecl_stack_frame_close(frame);
		return out;
	}
@)

cl_object
cl_eval(cl_object form)
{
	return si_eval_with_env(1, form);
}

@(defun constantp (arg &optional env)
	cl_object flag;
@
	switch (type_of(arg)) {
	case t_list:
		if (Null(arg)) {
			flag = Ct;
		} else if (CAR(arg) == @'quote') {
			flag = Ct;
		} else {
			flag = Cnil;
		}
		break;
	case t_symbol:
		flag = (arg->symbol.stype & stp_constant) ? Ct : Cnil;
		break;
	default:
		flag = Ct;
	}
	@(return flag)
@)
