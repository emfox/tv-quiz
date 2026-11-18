/*
 * su for this TV.
 *
 * /factory/su is a setuid copy of /system/bin/sh (mksh), so it hands out
 * euid 0 while leaving the real uid at 2000.  mksh drops privileges whenever
 * euid != ruid, so every nested shell loses root and `su -c cmd` silently
 * runs unprivileged.  Fixing the *real* uid is the whole point of this
 * wrapper: after setresuid(0, 0, 0) the shell sees ruid == euid and stops
 * caring, with no -p needed.
 *
 * Capabilities stay empty either way.  The shell domain has CapBnd=0xc0
 * (CAP_SETGID|CAP_SETUID only), and a bounding set cannot be raised by
 * exec'ing a setuid binary, so remount and init control remain out of reach
 * here -- use `device/root.sh -t` for those.
 *
 * Built freestanding on purpose: Android has no glibc, and a static glibc
 * binary drags in loader/NSS assumptions that do not belong in a setuid
 * program.  Only four syscalls are needed.
 */

#define SYS_EXIT      1
#define SYS_EXECVE   11
#define SYS_SETRESUID 164
#define SYS_SETRESGID 170

static long sc(long nr, long a, long b, long c)
{
	register long r7 __asm__("r7") = nr;
	register long r0 __asm__("r0") = a;
	register long r1 __asm__("r1") = b;
	register long r2 __asm__("r2") = c;

	__asm__ volatile("svc #0" : "+r"(r0)
			 : "r"(r7), "r"(r1), "r"(r2) : "memory");
	return r0;
}

void cstart(long *sp) __attribute__((used));

__attribute__((naked)) void _start(void)
{
	__asm__ volatile("mov r0, sp\n\tb cstart");
}

void cstart(long *sp)
{
	int argc = (int)sp[0];
	char **argv = (char **)(sp + 1);
	char **envp = argv + argc + 1;
	static char *nargv[64];
	int i, n = 0;

	/* Group first, then user: dropping the uid first would take the
	 * privilege needed to change the gid away. */
	sc(SYS_SETRESGID, 0, 0, 0);
	sc(SYS_SETRESUID, 0, 0, 0);

	nargv[n++] = "sh";
	for (i = 1; i < argc && n < 62; i++) {
		/* -p only ever mattered because mksh dropped privileges; with a
		 * real uid of 0 it is a no-op, so swallow it for compatibility. */
		if (i == 1 && argv[i][0] == '-' && argv[i][1] == 'p' &&
		    argv[i][2] == '\0')
			continue;
		nargv[n++] = argv[i];
	}
	if (n == 1)
		nargv[n++] = "-i";
	nargv[n] = 0;

	sc(SYS_EXECVE, (long)"/system/bin/sh", (long)nargv, (long)envp);
	sc(SYS_EXIT, 127, 0, 0);
}
