-- Add worker nodes to the cluster
-- Replace any existing workers first (idempotent)
DO $$
BEGIN
    -- Remove existing workers if they exist
    PERFORM citus_remove_node(nodename, nodeport) 
    FROM pg_dist_node 
    WHERE groupid != 0;  -- Don't remove coordinator
    
    -- Add worker nodes
    PERFORM citus_add_node('worker_citus1', 5432);
    PERFORM citus_add_node('worker_citus2', 5432);
    
    RAISE NOTICE 'Citus cluster initialized with % worker nodes', 
        (SELECT count(*) FROM pg_dist_node WHERE groupid != 0);
END
$$;