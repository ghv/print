![Print](https://media.giphy.com/media/lXiRLb0xFzmreM8k8/source.gif)
###### *Image credit: [gfaught](https://giphy.com/gfaught)*

`print` is a tool to publish a set of static files to an AWS S3 bucket and invalidate their cached copies in CloudFront.

This tool keeps track of the file time stamps that have been uploaded and only uploads files that have been
touched since the last time the tool was run.

The tool requires you to have already setup an S3 bucket for serving static content as well as a the associated CloudFront distribution.

## Why?

1. Take advantage of the scale, reliability, and performance of S3 and CloudFront
1. While these are not free services from AWS, they could be cost effective compared to maintaining and achieving the above on your own
1. `print` has a simple approach that is easy to setup and use
1. Might keep you from getting "✪ Daring Fireballed"

# Build

Run `make install` in the project's root folder to compile and install this tool in `/usr/local/bin`

# Setup

## Setup your AWS Credentials in Keychain

A one-time setup is required to save the AWS Access keys in your keychain. Run `print keychain [AWS Access Key ID]`. 
You then need to paste in the `AWS Access Secret` when prompted.

### Minimal IAM policy

You can limit the key's scope to the following policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PrintToolPolicy",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:ListBucket",
                "cloudfront:CreateInvalidation",
            ],
            "Resource": [
                "arn:aws:cloudfront::__AWS_ACCOUNT__:distribution/__DISTRIBUTION_ID__",
                "arn:aws:s3:::__BUCKET_NAME__",
                "arn:aws:s3:::__BUCKET_NAME__/*",
            ]
        }
    ]
}
```

## Content Configuration

You need to create a `contents.json` file at the root folder of your project.

### JSON Schema

You can use the [JSON Schema Validator](https://www.jsonschemavalidator.net) to validate your `contents.json` against this schema:

```json
{
    "$schema": "https://json-schema.org/draft/2020-12",
    "type": "object",
    "properties": {
        "region": { "type": "string" },
        "bucket": { "type": "string" },
        "cloudFront": { "type": "string" },
        "originPathFolder": { "type": "string" },
        "contents": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "folder": { "type": "string" },
                    "files": {
                        "type": "array",
                        "items": { "type": "string" }
                    }
                },
                "required": ["folder", "files"]
           }   
        }
    },
    "required": ["region", "bucket", "cloudFront", "originPathFolder", "contents"]
}
```

The root object should contain the following properties:

| Property | Description |
| ---------- | ------------- |
| `keychainItem` | Optional keychain item name that stores the AWS credentials to use. "AWS" is used if omitted.
| `region` | The region your S3 bucket was created in (e.g. `us-east-1`.) |
| `bucket` | The name of the S3 bucket to put your files in. |
| `cloudFront` | The CloudFront Distrbution ID that serves content from the specified bucket. |
| `originPathFolder` | An optional folder for cases where the same bucket could host QA and PROD or other site contents. The CloudFront distribution should also reflect this origin path. Leave as `""` if files are served from the entire bucket. |
| `contents` | An array containing the folders to create in the bucket and the files that should go into each of those folders. |

You can reference an environment variable that contains the desired value by specifiying the name of the variable with a `$` prefix. This is supported for the all but the `contents` properties of the root object.

Each element in the `contents` array should contain the following:

| Property | Description |
| ---------- | ------------- |
| `folder` | The path in the S3 bucket that will contain the files specified by the `files` property. |
| `files`  | An array of local file paths to be uploaded in `folder`. This could also be an array of two strings where the first is the local file path and the second is the remote file name to be uploaded in `folder`. The local file paths are relative to the `contents.json` folder. |

### Sample `contents.json`

This is the sample from the `TestSite` unit test resource:

```json
{
  "region": "$PRINTREGION",
  "bucket": "$PRINTBUCKET",
  "cloudFront": "$PRINTCLOUDFRONT",
  "originPathFolder": "$PRINTORIGINPATH",
  "contents": [
    {
      "folder": "",
      "files": [
        "index.html"
      ]
    },
    {
      "folder": "someFolder",
      "files": [
        "someFolderContents/index.html",
        [ "someFolderContents/index.html", "copy.html"]
      ]
    },
    {
      "folder": "someEmptyFolder",
      "files": [
      ]
    }
  ]
}
```

# Unit Test Environment Variables

The `TestSite` content configuration references the following environment variables in order to make it runable from your own AWS account.
You must provide these values if you want to run the `DeployerTests` test case.  

| Variable | Description |
| --------- | ------------- |
| `PRINTBUCKET` | The test bucket name  |
| `PRINTREGION` | The test region the bucket was created in |
| `PRINTCLOUDFRONT` | The CloudFront Distribution ID that serves the bucket contents |
| `PRINTORIGINPATH` | An optional folder for cases where the same bucket could host QA and PROD or other site contents. The CloudFront distribution should also specify this origin path. |

# Built-in Environment Variables

| Variable | Description |
| --------- | ------------- |
| `PRINTROOT` | Path to the root folder that contains the `contents.json` file. Set this variable if you want to run the tool from any folder, otherwise you must run this tool from the folder containing a `contents.json` file. |

# License

`print` is licensed under the Apache 2.0 License. Contributions welcome.

See [LICENSE.txt](LICENSE.txt) for license information.

See [CONTRIBUTORS.markdown](CONTRIBUTORS.markdown) for the ghv/print project authors.

See [NOTICES.markdown](NOTICES.markdown) for dependency license information.

# Thank You!
