# Infrastructure for Yandex Cloud Managed Service for Greenplum® cluster, Yandex Cloud Managed Service for PostgreSQL, and Data Transfer
#
# RU: https://cloud.yandex.ru/docs/data-transfer/tutorials/greenplum-to-postgresql
# EN: https://cloud.yandex.com/en/docs/data-transfer/tutorials/greenplum-to-postgresql

# Specify the following settings
locals {
  # Settings for Managed Service for Greenplum® cluster:
  gp_version  = "" # Set the Greenplum® version. For available versions, see the documentation main page: https://cloud.yandex.com/en/docs/managed-greenplum/.
  gp_password = "" # Set a password for the Greenplum® admin user

  # Settings for Managed Service for PostgreSQL cluster:
  pg_version  = "" # Set the PostgreSQL version. For available versions, see the documentation main page: https://cloud.yandex.com/en/docs/managed-postgresql/.
  pg_password = "" # Set a password for the PostgreSQL admin user

  # Specify these settings ONLY AFTER the clusters are created. Then run "terraform apply" command again.
  # You should set up the source endpoint using the GUI to obtain its ID
  gp_source_endpoint_id = "" # Set the source endpoint ID
  transfer_enabled      = 0  # Value '0' disables creating of transfer before the source endpoint is created manually. After that, set to '1' to enable transfer

  # The following settings are predefined. Change them only if necessary.
  mgp_network_name        = "mgp_network"        # Name of the network for the Greenplum® cluster
  mpg_network_name        = "mpg_network"        # Name of the network for the PostgreSQL cluster
  mgp_subnet_name         = "mgp_subnet-a"       # Name of the subnet for the Greenplum® cluster
  mpg_subnet_name         = "mpg_subnet-a"       # Name of the subnet for the PostgreSQL cluster
  mgp_security_group_name = "mgp-security-group" # Name of the security group for the Greenplum® cluster
  mpg_security_group_name = "mpg-security-group" # Name of the security group for the PostgreSQL cluster
  gp_cluster_name         = "mgp-cluster"        # Name of the Greenplum® cluster
  gp_username             = "gp-user"            # Name of the Greenplum® username
  pg_cluster_name         = "mpg-cluster"        # Name of the PostgreSQL cluster
  pg_db_name              = "db1"                # Name of the PostgreSQL cluster database
  pg_username             = "pg-user"            # Name of the PostgreSQL cluster username
  target_endpoint_name    = "pg-target-tf"       # Name of the target endpoint for the PostgreSQL cluster
  transfer_name           = "mgp-mpg-transfer"   # Name of the transfer from the Managed Service for Greenplum® cluster to the Managed Service for PostgreSQL cluster
}

# Network infrastructure

resource "yandex_vpc_network" "mgp_network" {
  description = "Network for the Managed Service for Greenplum® cluster"
  name        = local.mgp_network_name
}

resource "yandex_vpc_network" "mpg_network" {
  description = "Network for the Managed Service for PostgreSQL cluster"
  name        = local.mpg_network_name
}

resource "yandex_vpc_subnet" "mgp_subnet-a" {
  description    = "Subnet in ru-central1-a availability zone for the Managed Service for Greenplum® cluster"
  name           = local.mgp_subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mgp_network.id
  v4_cidr_blocks = ["10.128.0.0/18"]
}

resource "yandex_vpc_subnet" "mpg_subnet-a" {
  description    = "Subnet ru-central1-a availability zone for the Managed Service for PostgreSQL cluster"
  name           = local.mpg_subnet_name
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mpg_network.id
  v4_cidr_blocks = ["10.129.0.0/24"]
}

resource "yandex_vpc_security_group" "mgp_security_group" {
  description = "Security group for the Managed Service for Greenplum® cluster"
  network_id  = yandex_vpc_network.mgp_network.id
  name        = local.mgp_security_group_name


  ingress {
    description    = "Allow incoming traffic from members of the same security group"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to members of the same security group"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "mpg_security_group" {
  description = "Security group for the Managed Service for PostgreSQL"
  network_id  = yandex_vpc_network.mpg_network.id
  name        = local.mpg_security_group_name

  ingress {
    description    = "Allow incoming traffic from the port 6432"
    protocol       = "TCP"
    port           = 6432
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to members of the same security group"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Infrastructure for the Managed Service for Greenplum® cluster

resource "yandex_mdb_greenplum_cluster" "mgp-cluster" {
  description        = "Managed Service for Greenplum® cluster"
  name               = local.gp_cluster_name
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mgp_network.id
  zone               = "ru-central1-a"
  subnet_id          = yandex_vpc_subnet.mgp_subnet-a.id
  assign_public_ip   = true
  version            = local.gp_version
  master_host_count  = 2
  segment_host_count = 2
  segment_in_host    = 1
  master_subcluster {
    resources {
      resource_preset_id = "s3-c8-m32" # 8 vCPU, 32 GB RAM
      disk_size          = 100         # GB
      disk_type_id       = "network-ssd"
    }
  }
  segment_subcluster {
    resources {
      resource_preset_id = "s3-c8-m32" # 8 vCPU, 32 GB RAM
      disk_size          = 93          # GB
      disk_type_id       = "network-ssd-nonreplicated"
    }
  }

  user_name     = local.gp_username
  user_password = local.gp_password

  security_group_ids = [yandex_vpc_security_group.mgp_security_group.id]
}

# Infrastructure for the Managed Service for PostgreSQL cluster

resource "yandex_mdb_postgresql_cluster" "mpg-cluster" {
  description        = "Managed Service for PostgreSQL cluster"
  name               = "mpg-cluster"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mpg_network.id
  security_group_ids = [yandex_vpc_security_group.mpg_security_group.id]

  config {
    version = local.pg_version
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = "20"
    }
  }

  host {
    zone             = "ru-central1-a"
    subnet_id        = yandex_vpc_subnet.mpg_subnet-a.id
    assign_public_ip = true
  }
}

# Database of the Managed Service for PostgreSQL cluster
resource "yandex_mdb_postgresql_database" "pg-db" {
  cluster_id = yandex_mdb_postgresql_cluster.mpg-cluster.id
  name       = local.pg_db_name
  owner      = yandex_mdb_postgresql_user.pg-user.name
}

# User of the Managed Service for PostgreSQL cluster
resource "yandex_mdb_postgresql_user" "pg-user" {
  cluster_id = yandex_mdb_postgresql_cluster.mpg-cluster.id
  name       = local.pg_username
  password   = local.pg_password
}

# Data Transfer infrastructure

resource "yandex_datatransfer_endpoint" "pg_target" {
  description = "Target endpoint for the Managed Service for PostgreSQL cluster"
  name        = local.target_endpoint_name
  settings {
    postgres_target {
      connection {
        mdb_cluster_id = yandex_mdb_postgresql_cluster.mpg-cluster.id
      }
      database = yandex_mdb_postgresql_database.pg-db.name
      user     = yandex_mdb_postgresql_user.pg-user.name
      password {
        raw = local.pg_password
      }
    }
  }
}

resource "yandex_datatransfer_transfer" "mgp-mpg-transfer" {
  description = "Transfer from the Managed Service for Greenplum® to the Managed Service for PostgreSQL"
  count       = local.transfer_enabled
  name        = local.transfer_name
  source_id   = local.gp_source_endpoint_id
  target_id   = yandex_datatransfer_endpoint.pg_target.id
  type        = "SNAPSHOT_ONLY" # Copying data from the source Managed Service for Greenplum® database
}
