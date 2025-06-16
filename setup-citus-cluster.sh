#!/bin/bash

# Citus cluster setup script
set -e

echo "=== Setting up Citus Distributed Cluster ==="

# Function to check if a service is ready
check_service() {
    local service_name=$1
    local max_attempts=60
    local attempt=1
    
    echo "Checking if $service_name is ready..."
    while [ $attempt -le $max_attempts ]; do
        if docker compose exec -T "$service_name" pg_isready -U postgres > /dev/null 2>&1; then
            echo "✅ $service_name is ready!"
            return 0
        fi
        echo "⏳ Waiting for $service_name... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    echo "❌ $service_name failed to become ready after $max_attempts attempts"
    exit 1
}

# Step 1: Wait for all services to be ready
echo "Step 1: Waiting for all database services to be ready..."
check_service "coordinator_citus"
check_service "worker_citus1"
check_service "worker_citus2"

# Step 2: Clean up existing Citus metadata
echo "Step 2: Cleaning up existing Citus metadata..."
docker compose exec -T coordinator_citus psql -U postgres -d postgres << 'EOF'
-- Drop all shards
SELECT citus_drop_all_shards(pg_class.oid, nspname, relname)
FROM pg_class
JOIN pg_namespace ON pg_class.relnamespace = pg_namespace.oid
WHERE relkind = 'r' AND nspname = 'public';

-- Remove all nodes
DELETE FROM pg_dist_node;

-- Reset shard and placement metadata
DELETE FROM pg_dist_shard;
DELETE FROM pg_dist_placement;

-- Drop test table if it exists
DROP TABLE IF EXISTS test_distributed CASCADE;
EOF

# Step 3: Initialize Citus cluster
echo "Step 3: Initializing Citus distributed cluster..."
docker compose exec -T coordinator_citus psql -U postgres -d postgres << 'EOF'
-- Enable Citus extension
CREATE EXTENSION IF NOT EXISTS citus;

-- Add coordinator node
SELECT citus_add_node('coordinator_citus', 5432, 0, 'primary');

-- Add worker nodes
SELECT citus_add_node('worker_citus1', 5432);
SELECT citus_add_node('worker_citus2', 5432);

-- Verify worker count
DO $$
DECLARE
    worker_count int;
BEGIN
    SELECT count(*) INTO worker_count FROM pg_dist_node WHERE groupid != 0;
    RAISE NOTICE 'Citus cluster initialized with % worker nodes', worker_count;
    IF worker_count != 2 THEN
        RAISE EXCEPTION 'Expected 2 worker nodes, but found %', worker_count;
    END IF;
END
$$;
EOF

# Step 4: Verify cluster setup
echo "Step 4: Verifying cluster configuration..."
docker compose exec -T coordinator_citus psql -U postgres -d postgres -c "
SELECT 
    nodename, 
    nodeport, 
    groupid, 
    isactive,
    CASE WHEN isactive THEN '✅ Active' ELSE '❌ Inactive' END AS status
FROM pg_dist_node 
ORDER BY groupid;
"

# Step 5: Test distributed functionality
echo "Step 5: Testing distributed functionality..."
docker compose exec -T coordinator_citus psql -U postgres -d postgres << 'EOF'
-- Create a test distributed table
CREATE TABLE test_distributed (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Distribute the table across workers
SELECT create_distributed_table('test_distributed', 'id', shard_count := 4);

-- Insert test data
INSERT INTO test_distributed (data) 
VALUES ('test-data-1'), ('test-data-2'), ('test-data-3'), ('test-data-4'), ('test-data-5');

-- Show data distribution
SELECT COUNT(*) as total_rows FROM test_distributed;

-- Show shard distribution (better query)
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname IN ('public') AND tablename LIKE 'test_distributed_%'
ORDER BY tablename;

-- Also show from citus metadata
SELECT 
    logicalrelid::regclass as table_name,
    shardid,
    shardstorage,
    shardminvalue,
    shardmaxvalue
FROM pg_dist_shard 
WHERE logicalrelid = 'test_distributed'::regclass
ORDER BY shardid;
EOF

# Step 6: Check replication status
echo "Step 6: Checking replication setup..."
echo "Coordinator replication status:"
docker compose exec -T coordinator_citus psql -U postgres -d postgres -c "
SELECT 
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
"

echo "Worker 1 replication status:"
docker compose exec -T worker_citus1 psql -U postgres -d postgres -c "
SELECT 
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
"

echo "Worker 2 replication status:"
docker compose exec -T worker_citus2 psql -U postgres -d postgres -c "
SELECT 
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
"

# Check if standbys are running
echo "Checking standby container status..."
docker compose ps | grep standby

echo ""
echo "=== Citus cluster setup complete! ==="
echo "✅ Coordinator: Available through PgBouncer at localhost:6432"
echo "✔ Workers: Registered and ready for distributed queries"
echo "✔ Test table created and distributed across workers"
echo ""
echo "Connection examples:"
echo "  Direct coordinator: psql -h localhost -p 5432 -U postgres postgres"
echo "  Via PgBouncer:      psql -h localhost -p 6432 -U postgres postgres"
echo ""
echo "To test the cluster:"
echo "  docker compose exec coordinator_citus psql -U postgres -d postgres"
echo "  SELECT * FROM pg_dist_shard;"
echo "  SELECT * FROM test_distributed;"