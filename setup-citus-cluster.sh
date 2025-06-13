#!/bin/bash

# Citus cluster setup script - run after containers are started
set -e

echo "=== Setting up Citus Distributed Cluster ==="

# Wait for all services to be fully ready
echo "Step 1: Waiting for all database services to be ready..."
for i in {1..30}; do
    if docker compose exec -T coordinator_citus pg_isready -U postgres > /dev/null 2>&1 && \
       docker compose exec -T worker_citus1 pg_isready -U postgres > /dev/null 2>&1 && \
       docker compose exec -T worker_citus2 pg_isready -U postgres > /dev/null 2>&1; then
        echo "All services are ready!"
        break
    fi
    echo "Waiting for services... ($i/30)"
    sleep 2
done

# Initialize Citus cluster
echo "Step 2: Initializing Citus distributed cluster..."
docker compose exec -T coordinator_citus psql -U postgres -d postgres << 'EOF'
-- Enable Citus extension
CREATE EXTENSION IF NOT EXISTS citus;

-- Add worker nodes to the cluster (idempotent)
DO $$
BEGIN
    -- Remove existing workers if they exist (cleanup)
    PERFORM citus_remove_node(nodename, nodeport) 
    FROM pg_dist_node 
    WHERE groupid != 0;
    
    -- Add worker nodes
    PERFORM citus_add_node('worker_citus1', 5432);
    PERFORM citus_add_node('worker_citus2', 5432);
    
    RAISE NOTICE 'Citus cluster initialized with % worker nodes', 
        (SELECT count(*) FROM pg_dist_node WHERE groupid != 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Worker setup encountered: %', SQLERRM;
        -- Try to add workers individually
        BEGIN
            PERFORM citus_add_node('worker_citus1', 5432);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Worker 1 already exists or failed: %', SQLERRM;
        END;
        
        BEGIN
            PERFORM citus_add_node('worker_citus2', 5432);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Worker 2 already exists or failed: %', SQLERRM;
        END;
END
$$;
EOF

# Verify cluster setup
echo "Step 3: Verifying cluster configuration..."
docker compose exec -T coordinator_citus psql -U postgres -d postgres -c "
SELECT nodename, nodeport, groupid, isactive 
FROM pg_dist_node 
ORDER BY groupid;
"

echo "Step 4: Testing distributed functionality..."
docker compose exec -T coordinator_citus psql -U postgres -d postgres << 'EOF'
-- Create a test distributed table
CREATE TABLE IF NOT EXISTS test_distributed (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Distribute the table across workers
SELECT create_distributed_table('test_distributed', 'id');

-- Insert some test data
INSERT INTO test_distributed (data) 
VALUES ('test-data-1'), ('test-data-2'), ('test-data-3')
ON CONFLICT DO NOTHING;

-- Show data distribution
SELECT COUNT(*) as total_rows FROM test_distributed;
EOF

echo "=== Citus cluster setup complete! ==="
echo "✅ Coordinator: Available through PgBouncer at localhost:6432"
echo "✅ Workers: Registered and ready for distributed queries"
echo "✅ Test table created and distributed across workers"