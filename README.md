# OpenChamber + 9Router Deployment

This repository contains the configuration for deploying OpenChamber with 9Router on Coolify.

## Deployment Instructions

1. Fork this repository to your GitHub account
2. Connect your GitHub account to Coolify
3. Create a new project in Coolify using this repository
4. Before deploying, set the following environment variables in Coolify:
   - `OPENCHAMBER_UI_PASSWORD` - Set a strong password for the OpenChamber UI
   - (Optional) `WEBUI_SECRET_KEY` - Secret key for session encryption
   - (Optional) `BETTER_AUTH_SECRET` - Required for DeerFlow
   - (Optional) `DEER_FLOW_INTERNAL_AUTH_TOKEN` - Required for DeerFlow

## Configuration

The `docker-compose.yaml` file defines the following services:
- **9router** - AI router/proxy (port 8085)
- **openchamber** - AI coding assistant (port 3051)

## Security

The OpenChamber service is configured with UI authentication to prevent unauthorized access. Make sure to set a strong password for `OPENCHAMBER_UI_PASSWORD`.

## Access

After deployment, you can access:
- OpenChamber at: `http://your-coolify-domain:3051`
- 9Router at: `http://your-coolify-domain:8085`

## Troubleshooting

If you encounter issues:
1. Check the Coolify logs for error messages
2. Ensure all required environment variables are set
3. Verify that ports 3051 and 8085 are not blocked by your firewall
