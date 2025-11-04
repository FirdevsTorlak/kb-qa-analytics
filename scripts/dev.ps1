param(
  [ValidateSet("up","down","reseed","ps","shell","dump","restore")] [string]$cmd = "up"
)

switch ($cmd) {
  "up" {
    docker compose up -d
    docker compose ps
  }
  "down" {
    docker compose down -v
  }
  "reseed" {
    docker compose down -v
    docker compose up -d
  }
  "ps" {
    docker compose ps
  }
  "shell" {
    docker exec -it kbqa_db psql -U postgres -d kb
  }
  "dump" {
    docker exec -it kbqa_db pg_dump -U postgres -d kb -Fc > kb.dump
    Write-Host "Dump created: kb.dump"
  }
  "restore" {
    docker exec -it kbqa_db dropdb  -U postgres --if-exists kb_restored
    docker exec -it kbqa_db createdb -U postgres kb_restored
    docker cp .\kb.dump kbqa_db:/tmp/kb.dump
    docker exec -it kbqa_db pg_restore -U postgres --no-owner --no-privileges --single-transaction -d kb_restored /tmp/kb.dump
    Write-Host "Restored into kb_restored"
  }
}
