# achievements-ty

Backend platform to track and aggregate gaming achievements across networks.

## What I built
- API-oriented architecture for achievement ingestion and tracking.
- Integrations prepared for PSN, Xbox, and RetroAchievements.
- Job/queue and persistence setup with Redis + Prisma.
- Monorepo structure with Nx for scalable backend modules.

## Tech
Node.js, TypeScript, NestJS, Nx, Prisma, Redis, Docker Compose.

## Run
```bash
cd achievements-app-main
yarn install
yarn docker:up
yarn dev:api
```
