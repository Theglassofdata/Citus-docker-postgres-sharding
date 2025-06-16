# Citus Distributed PostgreSQL Cluster with High Availability

A production-ready distributed PostgreSQL setup using Citus with streaming replication, connection pooling, and service discovery.

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   PgBouncer     │    │   Coordinator    │    │      etcd       │
│ (Port 6432)     │◄──►│     Citus        │◄──►│ Service Discovery│
│ Connection Pool │    │   (Port 5432)    │    │   (Port 2379)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                       ┌────────┴────────┐
                       ▼                 ▼
              ┌─────────────────┐ ┌─────────────────┐
              │  Worker Node 1  │ │  Worker Node 2  │
              │   (Port 5432)   │ │   (Port 5432)   │
              └─────────────────┘ └─────────────────┘
                       │                 │
                       ▼                 ▼
              ┌─────────────────┐ ┌─────────────────┐
              │   Standby 1     │ │   Standby 2     │
              │ (Streaming Rep) │ │ (Streaming Rep) │
              └─────────────────┘ └─────────────────┘
```

## 🚀 Features

- **Distributed Computing**: Horizontal scaling across multiple PostgreSQL nodes
- **High Availability**: Streaming replication with automatic failover
- **Connection Pooling**: PgBouncer for efficient connection management
- **Service Discovery**: etcd for dynamic service registration
- **Production Ready**: Comprehensive health checks and monitoring
- **Easy Deployment**: One-command Docker Compose setup

## 📋 Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- At least 4GB RAM available
- Ports 5432, 6432, 2379, 2380 available

## 🔧 Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd citus-distributed-cluster

# Create required directories
mkdir -p secrets config init-scripts pgbouncer

# Set up password file
echo "postgres" > secrets/db_password.txt
chmod 600 secrets/db_password.txt
```

### 2. Launch the Cluster

```bash
# Start all services
docker compose up -d

# Wait for services to be ready (30-60 seconds)
```

### 3. Initialize the Citus Cluster

```bash
# Run the cluster setup script
chmod +x setup-citus-cluster.sh
./setup-citus-cluster.sh
```

### 4. Verify the Setup

```bash
# Connect via PgBouncer (recommended)
psql -h localhost -p 6432 -U postgres postgres

# Or connect directly to coordinator
psql -h localhost -p 5432 -U postgres postgres
```

## 🛠️ Configuration Files

### Core Configuration
- `docker-compose.yml` - Main orchestration file
- `config/postgresql.conf` - PostgreSQL server configuration
- `config/pg_hba.conf` - Authentication rules

### Initialization Scripts
- `init-scripts/init.sql` - Creates Citus extension
- `init-scripts/init-citus-cluster.sql` - Sets up worker nodes

### Connection Pooling
- `pgbouncer/pgbouncer.ini` - PgBouncer configuration
- `pgbouncer/userlist.txt` - User authentication for PgBouncer

## 📊 Services Overview

| Service | Container Name | Port | Purpose |
|---------|---------------|------|---------|
| Coordinator | `coordinator_citus` | 5432 | Main Citus coordinator node |
| Worker 1 | `worker_citus1` | 5432 | First worker node |
| Worker 2 | `worker_citus2` | 5432 | Second worker node |
| Standby 1 | `worker_citus1_standby` | 5432 | Replica of worker 1 |
| Standby 2 | `worker_citus2_standby` | 5432 | Replica of worker 2 |
| PgBouncer | `pgbouncer` | 6432 | Connection pooler |
| etcd | `etcd` | 2379/2380 | Service discovery |
| PostgreSQL | `postgres` | 5432 | Standalone PostgreSQL |

## 📈 Usage Examples

### Creating Distributed Tables

```sql
-- Connect to the coordinator
\c postgres

-- Create a distributed table
CREATE TABLE events (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    event_type TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Distribute the table across workers
SELECT create_distributed_table('events', 'user_id');

-- Insert test data
INSERT INTO events (user_id, event_type) 
VALUES 
    (1, 'login'), (2, 'purchase'), (3, 'logout'),
    (4, 'signup'), (5, 'purchase'), (6, 'login');

-- Query distributed data
SELECT event_type, COUNT(*) 
FROM events 
GROUP BY event_type;
```

### Checking Cluster Status

```sql
-- View all nodes in the cluster
SELECT nodename, nodeport, isactive 
FROM pg_dist_node;

-- Check shard distribution
SELECT 
    logicalrelid::regclass as table_name,
    count(*) as shard_count
FROM pg_dist_shard 
GROUP BY logicalrelid;

-- View replication status
SELECT * FROM pg_stat_replication;
```

## 🔍 Monitoring & Maintenance

### Health Checks

```bash
# Check all service status
docker compose ps

# View logs for specific service
docker compose logs coordinator_citus
docker compose logs pgbouncer

# Check PostgreSQL connectivity
docker compose exec coordinator_citus pg_isready -U postgres
```

### Backup & Recovery

```bash
# Backup coordinator
docker compose exec coordinator_citus pg_dump -U postgres postgres > backup.sql

# Backup specific worker
docker compose exec worker_citus1 pg_dump -U postgres postgres > worker1_backup.sql
```

### Scaling Operations

```bash
# Add a new worker node (modify docker-compose.yml first)
docker compose up -d worker_citus3

# Register the new worker in Citus
docker compose exec coordinator_citus psql -U postgres -c \
  "SELECT citus_add_node('worker_citus3', 5432);"

# Rebalance shards
docker compose exec coordinator_citus psql -U postgres -c \
  "SELECT rebalance_table_shards('your_table_name');"
```

## 🔒 Security Considerations

### Production Deployment

1. **Change Default Passwords**
   ```bash
   # Generate strong password
   openssl rand -base64 32 > secrets/db_password.txt
   ```

2. **Configure SSL/TLS**
   - Add SSL certificates to `config/` directory
   - Update `postgresql.conf` with SSL settings

3. **Network Security**
   - Use Docker networks with restricted access
   - Configure firewall rules
   - Enable SSL for all connections

4. **Authentication**
   - Update `pg_hba.conf` for production rules
   - Use certificate-based authentication
   - Configure PgBouncer with proper auth methods

## 🐛 Troubleshooting

### Common Issues

**Services won't start:**
```bash
# Check Docker resources
docker system df
docker system prune

# Restart specific service
docker compose restart coordinator_citus
```

**Replication issues:**
```bash
# Check replication status
docker compose exec worker_citus1 psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Reset standby
docker compose stop worker_citus1_standby
docker volume rm citus-cluster_worker_citus1_standby_data
docker compose up -d worker_citus1_standby
```

**Connection problems:**
```bash
# Test direct connection
docker compose exec coordinator_citus psql -U postgres -l

# Test via PgBouncer
psql -h localhost -p 6432 -U postgres -c "SHOW POOLS;"
```

### Performance Tuning

1. **PostgreSQL Settings** (in `postgresql.conf`)
   ```
   shared_buffers = 25% of total RAM
   effective_cache_size = 75% of total RAM
   work_mem = Total RAM / max_connections / 4
   ```

2. **PgBouncer Settings** (in `pgbouncer.ini`)
   ```
   max_client_conn = 1000
   default_pool_size = 20
   pool_mode = transaction
   ```

## 📚 Additional Resources

- [Citus Documentation](https://docs.citusdata.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [PgBouncer Documentation](https://www.pgbouncer.org/)
- [Docker Compose Reference](https://docs.docker.com/compose/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
- Create an issue in this repository
- Check existing issues and discussions
- Review the troubleshooting section above

---

**⚡ Quick Commands Reference:**

```bash
# Start cluster
docker compose up -d

# Setup Citus
./setup-citus-cluster.sh

# Connect to database
psql -h localhost -p 6432 -U postgres postgres

# Check status
docker compose ps

# View logs
docker compose logs -f coordinator_citus

# Stop cluster
docker compose down
```