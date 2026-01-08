#!/usr/bin/env python3
"""
Apple Music Developer Token Generator

This script generates a JWT token for Apple Music API authentication.

Requirements:
- PyJWT library: pip install PyJWT
- Your Apple Developer Account credentials:
  1. Team ID (10 characters)
  2. Key ID (10 characters)
  3. Private Key (.p8 file)

Setup:
1. Go to https://developer.apple.com/account
2. Navigate to Certificates, Identifiers & Profiles
3. Click on Keys (under Keys section)
4. Click the + button to create a new key
5. Enable "MusicKit" checkbox
6. Download the .p8 file (keep it secure!)
7. Note the Key ID (displayed after creation)
8. Note your Team ID (in the top right of the page)

Usage:
python scripts/generate_apple_music_token.py \
    --team-id YOUR_TEAM_ID \
    --key-id YOUR_KEY_ID \
    --private-key-path /path/to/AuthKey_KEYID.p8

The generated token is valid for 6 months (configurable).
"""

import jwt
import time
import argparse
from datetime import datetime, timedelta


def generate_token(team_id: str, key_id: str, private_key_path: str, expiry_months: int = 6) -> str:
    """
    Generate an Apple Music Developer Token (JWT)

    Args:
        team_id: Your Apple Developer Team ID (10 characters)
        key_id: Your MusicKit Key ID (10 characters)
        private_key_path: Path to your .p8 private key file
        expiry_months: Token expiry in months (max 6 months for Apple Music)

    Returns:
        JWT token string
    """

    # Read the private key
    try:
        with open(private_key_path, 'r') as f:
            private_key = f.read()
    except FileNotFoundError:
        print(f"❌ Error: Private key file not found: {private_key_path}")
        exit(1)
    except Exception as e:
        print(f"❌ Error reading private key: {e}")
        exit(1)

    # Current time
    time_now = int(time.time())

    # Token expiry (max 6 months for Apple Music)
    if expiry_months > 6:
        print("⚠️  Warning: Token expiry > 6 months. Setting to 6 months (Apple's maximum).")
        expiry_months = 6

    time_expired = time_now + (expiry_months * 30 * 24 * 60 * 60)  # Approximate months

    # JWT headers
    headers = {
        "alg": "ES256",
        "kid": key_id
    }

    # JWT payload
    payload = {
        "iss": team_id,  # Issuer (Team ID)
        "iat": time_now,  # Issued at
        "exp": time_expired  # Expiration
    }

    # Generate the token
    try:
        token = jwt.encode(payload, private_key, algorithm='ES256', headers=headers)
        return token
    except Exception as e:
        print(f"❌ Error generating token: {e}")
        exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Generate Apple Music Developer Token',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument(
        '--team-id',
        required=True,
        help='Your Apple Developer Team ID (10 characters)'
    )

    parser.add_argument(
        '--key-id',
        required=True,
        help='Your MusicKit Key ID (10 characters)'
    )

    parser.add_argument(
        '--private-key-path',
        required=True,
        help='Path to your .p8 private key file'
    )

    parser.add_argument(
        '--expiry-months',
        type=int,
        default=6,
        help='Token expiry in months (default: 6, max: 6)'
    )

    args = parser.parse_args()

    # Validate Team ID and Key ID format
    if len(args.team_id) != 10:
        print(f"❌ Error: Team ID must be 10 characters (got {len(args.team_id)})")
        exit(1)

    if len(args.key_id) != 10:
        print(f"❌ Error: Key ID must be 10 characters (got {len(args.key_id)})")
        exit(1)

    print("🔐 Generating Apple Music Developer Token...")
    print(f"   Team ID: {args.team_id}")
    print(f"   Key ID: {args.key_id}")
    print(f"   Private Key: {args.private_key_path}")
    print(f"   Expiry: {args.expiry_months} months")
    print()

    # Generate token
    token = generate_token(
        team_id=args.team_id,
        key_id=args.key_id,
        private_key_path=args.private_key_path,
        expiry_months=args.expiry_months
    )

    # Calculate expiry date
    expiry_date = datetime.now() + timedelta(days=args.expiry_months * 30)

    print("✅ Token generated successfully!")
    print()
    print("=" * 80)
    print("APPLE_MUSIC_DEVELOPER_TOKEN=")
    print(token)
    print("=" * 80)
    print()
    print(f"📅 Token expires: {expiry_date.strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    print("📝 Next steps:")
    print("   1. Copy the token above")
    print("   2. Add it to your .env file:")
    print("      APPLE_MUSIC_DEVELOPER_TOKEN=<paste_token_here>")
    print("   3. Keep the token secure - do not commit it to version control")
    print("   4. Regenerate before expiry date")
    print()


if __name__ == "__main__":
    main()
