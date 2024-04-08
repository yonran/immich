import { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/postgres-adapter';
import { ServerOptions } from 'socket.io';
import { DataSource } from 'typeorm';
import { PostgresDriver } from 'typeorm/driver/postgres/PostgresDriver.js';

export class WebSocketAdapter extends IoAdapter {
  constructor(private app: INestApplicationContext) {
    super(app);
  }

  createIOServer(port: number, options?: ServerOptions): any {
    const server = super.createIOServer(port, options);
    const pool = (this.app.get(DataSource).driver as PostgresDriver).master;
    // don't make a pg_notify statement (which triggers a write to disk) every 5s
    // https://github.com/immich-app/immich/issues/2128
    // https://github.com/immich-app/immich/discussions/5989
    server.adapter(createAdapter(pool, { heartbeatInterval: 2 * 60 * 60 * 1000, heartbeatTimeout: (2 * 60 + 2) * 60 * 1000 }));
    return server;
  }
}
