![Print](https://media.giphy.com/media/lXiRLb0xFzmreM8k8/source.gif)
###### *Image credit: [gfaught](https://giphy.com/gfaught)*

**UPDATE:** I renamed the command line tool from `print` to `printer` to avoid the `zsh` shell built-in command. Everything else is unchanged.

Print is a tool to publish static files to an AWS S3 bucket and invalidate their cached copies in CloudFront.

This tool caches the file's timestamp when uploaded and only uploads a new copy if the current timestamp does not match the cached timestamp.

You must create a private S3 bucket that serves static content through the associated CloudFront distribution.
This tool only uploads changed files to the S3 bucket and invalidates the related cache nodes.

## Why?

1. Take advantage of the scale, reliability, and performance of S3 and CloudFront
2. While these are not free services from AWS, they could be cost-effective compared to maintaining and achieving the above on your own
3. "Print" has a simple approach that is easy to set up and use
4. It might keep you from getting "✪ Daring Fireballed"

# Build

Run `make install` in the project's root folder to compile and install this tool in `/usr/local/bin`

# Setup

## Set up your AWS Credentials in Keychain

A one-time setup is required to save the AWS Access keys in your keychain for each AWS key you use. The default Keychain item is "AWS", and you can specify an alternate item for each content configuration file.
To save the key to an alternate Keychain item, add the `--keychain-item [your_item_name]` in the `[options]` part of the command and add the name in the `keychainItem` property of your content configuration file.
Run `printer keychain [options] [AWS Access Key ID]` and then paste in the `AWS Access Secret` when prompted.

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
                "s3:DeleteObject",
                "s3:ListBucket",
                "cloudfront:CreateInvalidation"
            ],
            "Resource": [
                "arn:aws:cloudfront::__AWS_ACCOUNT__:distribution/__DISTRIBUTION_ID__",
                "arn:aws:s3:::__BUCKET_NAME__",
                "arn:aws:s3:::__BUCKET_NAME__/*"
            ]
        }
    ]
}
```

## Content Configuration

You need to create a `contents.json` file in the root folder of your project.

### JSON Schema

You can use the [JSON Schema Validator](https://www.jsonschemavalidator.net) to validate your `contents.json` against this schema:

```json
{
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
        "keychainItem": { "type": "string" },
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
                        "items": { 
                            "anyOf": [
                                {
                                    "type": "string"
                                },
                                {
                                    "type": "array",
                                    "items": {
                                        "type": "string"
                                    },
                                    "minItems": 2,
                                    "maxItems": 2
                                }
                            ]
                        }
                    },
                    "compactInvalidation": { "type": "boolean" },
                    "prune": { "type": "boolean" }
                },
                "required": ["folder", "files"]
           }   
        }
    },
    "required": ["region", "bucket", "cloudFront", "originPathFolder", "contents"]
}
```

The root object should contain the following properties:

| Property           | Description                                                                                                                                                                                                                 |
|--------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `keychainItem`     | Optional keychain item name that stores the AWS credentials. "AWS" is used if omitted.                                                                                                                                      |
| `region`           | The region your S3 bucket was created in (e.g. `us-east-1`.)                                                                                                                                                                |
| `bucket`           | The name of the S3 bucket to put your files in.                                                                                                                                                                             |
| `cloudFront`       | The CloudFront Distribution ID that serves content from the specified bucket.                                                                                                                                               |
| `originPathFolder` | An optional folder for cases where the same bucket could host QA, PROD, or other site contents. The CloudFront distribution should also reflect this origin path. Leave as `""` if files are served from the entire bucket. |
| `contents`         | An array containing the folders to create in the bucket and the files that should go into each of those folders.                                                                                                            |

You can reference an environment variable containing the desired value by specifying the environment variable's name with a `$` prefix. You can use the environment variable indirection for all root properties that accept a string value.

Each element in the `contents` array should contain the following:

| Property              | Description                                                                                                                                                                                                                                                                                                                  |
|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `folder`              | The path in the S3 bucket that will contain the files specified by the `files` property.                                                                                                                                                                                                                                     |
| `files`               | An array of local file paths to be uploaded in `folder`. Each element in this array can be either a string containing the local file path or an array of two strings where the first element is the local file path and the second is the remote file name. The local file paths are relative to the `contents.json` folder. |
| `prune`               | When set to `true`, deletes all files from the bucket in this `folder` that are no longer specified when comparing the two `content.json` files. The default value is `false` if the key is omitted.                                                                                                                         |
| `compactInvalidation` | When set to `true`, invalidates everything under this folder rather than invalidating individual files when two or more files have changed. The default value is `false` if the key is omitted.                                                                                                                              |

### Deleting Files from the Bucket

If you want to delete files from the bucket that are no longer part of your distribution, you will need to do two things:

1. Add the `prune` property to the `contents` array element for each folder where you want obsolete files deleted from your bucket.
2. Since the `contents.json` defines the current set of files to upload you must first copy or rename the current one to `contents.old.json` and when making changes or building a new `contents.json`.

This works best when you generate the `contents.json` file as part of your build process.

Every time you run Print (command line tool is called `printer`) to deploy changed files, it will compare the two files and any target files that are not in the new `contents.json` file will be deleted from the bucket. The `contents.old.json` file will be deleted after the upload is complete. The delete operation will only be performed if there exists a `contents.old.json` file, and it has at least one folder with the `prune` property set to `true`.

### Sample `contents.json`

The following is the `contents.json` file from the `TestSite` unit test resource:

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

The `TestSite` content configuration references the following environment variables to make it runnable from your AWS account.
You must provide these values to run the `DeployerTests` test case.  

| Variable          | Description                                                                                                                                                       |
|-------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `PRINTBUCKET`     | The test bucket name                                                                                                                                              |
| `PRINTREGION`     | The region you created your S3 bucket in                                                                                                                          |
| `PRINTCLOUDFRONT` | The CloudFront Distribution ID that serves the bucket contents                                                                                                    |
| `PRINTORIGINPATH` | An optional folder for cases where the same bucket could host QA, PROD, or other site contents. The CloudFront distribution should also specify this origin path. |

# Built-in Environment Variables

| Variable    | Description                                                                                                                                                                                                         |
|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `PRINTROOT` | Path to the root folder that contains the `contents.json` file. Set this variable if you want to run the tool from any folder. Otherwise, you must run this tool from the folder containing a `contents.json` file. |

# License

Print is licensed under the Apache 2.0 License. Contributions welcome.

See [LICENSE.txt](LICENSE.txt) for license information.

See [CONTRIBUTORS.markdown](CONTRIBUTORS.markdown) for authors of the ghv/print project.

See [NOTICES.markdown](NOTICES.markdown) for dependency license information.

# Thank You!
