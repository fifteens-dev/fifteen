#!/bin/bash
# Spotify Credential Tester
# Usage: ./test_spotify_creds.sh CLIENT_ID CLIENT_SECRET

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 CLIENT_ID CLIENT_SECRET"
    echo "Example: $0 abc123... def456..."
    exit 1
fi

CLIENT_ID="$1"
CLIENT_SECRET="$2"

echo "Testing Spotify credentials..."
echo "Client ID: ${CLIENT_ID:0:10}..."
echo "Client Secret: ${CLIENT_SECRET:0:10}..."
echo ""

# Test using the same method as Flutter app
curl -X POST "https://accounts.spotify.com/api/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" \
  2>/dev/null | python3 -m json.tool

echo ""
echo "If you see an access_token above, the credentials are valid!"
echo "If you see 'invalid_client', the credentials are not working."
