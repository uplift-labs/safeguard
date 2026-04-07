# API Reference

## Authentication

All endpoints require a Bearer token in the Authorization header.

```bash
curl -H "Authorization: Bearer $TOKEN" https://api.example.com/v1/users
```

## Rate Limits

- 100 requests per minute per API key
- 429 Too Many Requests response when exceeded
