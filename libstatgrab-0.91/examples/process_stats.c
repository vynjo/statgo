/*
 * i-scream libstatgrab
 * http://www.i-scream.org
 * Copyright (C) 2000-2013 i-scream
 * Copyright (C) 2010-2013 Jens Rehsack
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 *
 * $Id$
 */

#include <stdio.h>
#include <statgrab.h>
#include <stdlib.h>
#include <unistd.h>

#include "helpers.h"

static int quit;

int main(int argc, char **argv){

	extern char *optarg;
	int c;

	int delay = 1;
	sg_process_count *process_stat;

	while ((c = getopt(argc, argv, "d:")) != -1){
		switch (c){
			case 'd':
				delay = atoi(optarg);
				break;
		}
	}

	/* Initialise helper - e.g. logging, if any */
	sg_log_init("libstatgrab-examples", "SGEXAMPLES_LOG_PROPERTIES", argc ? argv[0] : NULL);

	/* Initialise statgrab */
	sg_init(1);

	/* Drop setuid/setgid privileges. */
	if (sg_drop_privileges() != SG_ERROR_NONE)
		sg_die("Error. Failed to drop privileges", 1);

	register_sig_flagger( SIGINT, &quit );

	if( (process_stat = sg_get_process_count()) == NULL )
		sg_die("Failed to get process list", 1);

	while( (process_stat = sg_get_process_count()) != NULL){
		int ch;
		printf("Running:%3llu \t", process_stat->running);
		printf("Sleeping:%5llu \t",process_stat->sleeping);
		printf("Stopped:%4llu \t", process_stat->stopped);
		printf("Zombie:%4llu \t", process_stat->zombie);
		printf("Total:%5llu\n", process_stat->total);
		ch = inp_wait(delay);
		if( quit || (ch == 'q') )
			break;
	}

	exit(0);
}
