/* -*- mode: c; c-basic-offset: 8 -*- */
/*
    mailbox.d -- thread communication queue
*/
/*
    Copyright (c) 2012, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#define AO_ASSUME_WINDOWS98 /* We need this for CAS */
#include <ecl/ecl.h>
#include <ecl/internal.h>

#if !defined(AO_HAVE_fetch_and_add1)
#error "Cannot implement mailboxs without AO_fetch_and_add1_full"
#endif

static ECL_INLINE void
FEerror_not_a_mailbox(cl_object mailbox)
{
        FEwrong_type_argument(@'mp::mailbox', mailbox);
}

cl_object
ecl_make_mailbox(cl_object name, cl_fixnum count)
{
	cl_object output = ecl_alloc_object(t_mailbox);
	cl_fixnum mask;
	for (mask = 1; mask < count; mask <<= 1) {}
	if (mask == 1)
	  mask = 63;
	count = mask + 1;
	output->mailbox.name = name;
	output->mailbox.data = si_make_vector(Ct, /* element type */
					      MAKE_FIXNUM(count), /* size */
					      Cnil, /* adjustable */
					      Cnil, /* fill pointer */
					      Cnil, /* displaced to */
					      Cnil); /* displacement */
	output->mailbox.reader_semaphore =
	  ecl_make_semaphore(name, 0);
	output->mailbox.writer_semaphore =
	  ecl_make_semaphore(name, count);
	output->mailbox.read_pointer = 0;
	output->mailbox.write_pointer = 1;
	output->mailbox.mask = mask;
        return output;
}

@(defun mp::make-mailbox (&key name (count MAKE_FIXNUM(128)))
@
{
	@(return ecl_make_mailbox(name, fixnnint(count)))
}
@)

cl_object
mp_mailbox_name(cl_object mailbox)
{
	cl_env_ptr env = ecl_process_env();
	unlikely_if (type_of(mailbox) != t_mailbox) {
		FEerror_not_a_mailbox(mailbox);
	}
        ecl_return1(env, mailbox->mailbox.name);
}

cl_object
mp_mailbox_count(cl_object mailbox)
{
	cl_env_ptr env = ecl_process_env();
	unlikely_if (type_of(mailbox) != t_mailbox) {
		FEerror_not_a_mailbox(mailbox);
	}
	ecl_return1(env, MAKE_FIXNUM(mailbox->mailbox.data->vector.dim));
}

cl_object
mp_mailbox_empty_p(cl_object mailbox)
{
	cl_env_ptr env = ecl_process_env();
	unlikely_if (type_of(mailbox) != t_mailbox) {
		FEerror_not_a_mailbox(mailbox);
	}
	ecl_return1(env, mailbox->mailbox.reader_semaphore->semaphore.counter? Cnil : Ct);
}

cl_object
mp_mailbox_read(cl_object mailbox)
{
	cl_env_ptr env = ecl_process_env();
	cl_fixnum ndx;
	cl_object output;
	unlikely_if (type_of(mailbox) != t_mailbox) {
		FEerror_not_a_mailbox(mailbox);
	}
	mp_wait_on_semaphore(mailbox->mailbox.reader_semaphore);
	{
		ndx = AO_fetch_and_add1((AO_t*)&mailbox->mailbox.read_pointer) &
			mailbox->mailbox.mask;
		output = mailbox->mailbox.data->vector.self.t[ndx];
	}
	mp_signal_semaphore(1, mailbox->mailbox.writer_semaphore);
	ecl_return1(env, output);
}

cl_object
mp_mailbox_send(cl_object mailbox, cl_object msg)
{
	cl_env_ptr env = ecl_process_env();
	cl_fixnum ndx;
	unlikely_if (type_of(mailbox) != t_mailbox) {
		FEerror_not_a_mailbox(mailbox);
	}
	mp_wait_on_semaphore(mailbox->mailbox.writer_semaphore);
	{
		ndx = AO_fetch_and_add1((AO_t*)&mailbox->mailbox.write_pointer) &
			mailbox->mailbox.mask;
		mailbox->mailbox.data->vector.self.t[ndx] = msg;
	}
	mp_signal_semaphore(1, mailbox->mailbox.reader_semaphore);
	ecl_return0(env);
}