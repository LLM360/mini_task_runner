#!/usr/bin/env python3
"""presign.py <s3-url> <region> <seconds>: sign permission to upload into one S3 folder.

Prints the lines `run` adds to the box's /root/.env. With them, box/upload.sh can POST files whose
names start with <s3-url>/ to S3 until <seconds> from now, and can do nothing else: no read, no
list, no delete, no other folder. The box never holds an AWS key, only this signature, so it works
for credentials that can't call sts:GetFederationToken or take on a role. <region> is the bucket's.
Signs with the credentials in the environment (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and, for
temporary ones, AWS_SESSION_TOKEN). S3 takes at most 5 GB in one POST.
"""
import base64, datetime, hashlib, hmac, json, os, sys

url, region, seconds = sys.argv[1], sys.argv[2], int(sys.argv[3])
bucket, _, folder = url.removeprefix("s3://").partition("/")
key_id, secret = os.environ["AWS_ACCESS_KEY_ID"], os.environ["AWS_SECRET_ACCESS_KEY"]
token = os.environ.get("AWS_SESSION_TOKEN", "")

now = datetime.datetime.now(datetime.timezone.utc)
day = now.strftime("%Y%m%d")
fields = {
    "x-amz-algorithm": "AWS4-HMAC-SHA256",
    "x-amz-credential": f"{key_id}/{day}/{region}/s3/aws4_request",
    "x-amz-date": now.strftime("%Y%m%dT%H%M%SZ"),
}
if token:
    fields["x-amz-security-token"] = token
policy = {
    "expiration": (now + datetime.timedelta(seconds=seconds)).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "conditions": [{"bucket": bucket}, ["starts-with", "$key", folder.rstrip("/") + "/"],
                   ["content-length-range", 0, 5 * 1024**3], *({k: v} for k, v in fields.items())],
}
fields["policy"] = base64.b64encode(json.dumps(policy).encode()).decode()

signing_key = ("AWS4" + secret).encode()
for part in (day, region, "s3", "aws4_request"):
    signing_key = hmac.new(signing_key, part.encode(), hashlib.sha256).digest()
fields["x-amz-signature"] = hmac.new(signing_key, fields["policy"].encode(), hashlib.sha256).hexdigest()

print(f"RECORD_POST_URL='https://{bucket}.s3.{region}.amazonaws.com/'")
print(f"RECORD_POST_FOLDER='{folder.rstrip('/')}'")
print(f"RECORD_POST_FIELDS='{json.dumps(fields)}'")
