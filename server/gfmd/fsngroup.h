/*
 * $Id$
 */

/*
 * Replication scheduler:
 */
struct inode;
struct host;
struct file_copy;
void fsngroup_replicate_file(
	struct inode *, struct host *, const char *,
	int, struct host **, struct file_copy *, int);

/*
 * Server side RPC stubs:
 */
struct peer;
gfarm_error_t gfm_server_fsngroup_get_all(
	struct peer *, int, int);
gfarm_error_t gfm_server_fsngroup_get_by_hostname(
	struct peer *, int, int);
gfarm_error_t gfm_server_fsngroup_modify(
	struct peer *, int, int);
