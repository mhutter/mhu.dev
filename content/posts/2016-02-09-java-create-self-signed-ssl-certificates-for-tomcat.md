+++
title = "Java: Create self-signed TLS/SSL certificates for Tomcat"
description = "A quick guide on how to generate a self-signed TLS certificate using the Java keytool and how to configure it in Tomcat."
[taxonomies]
tags = ["java", "tls"]
+++

To use an TLS certificate with Tomcat, you need to store it in a Java keystore File. You can generate both the keystore and the certificate using the Java command `keytool`.


## Step 0: Find your `keytool`

Make sure you have Java and `keytool` command (ships with Java) installed. If you installed the JDK or JRE yourself it may not be in your `$PATH`.

For example, my `keytool` is in `./jdk1.8/bin/`.

## Step 1: Generate the keystore and the certificate

Before we begin, a note about the "alias" and the "common name" of the certificate:

- The **alias** is simply a "label" used by Java to identify a specific certificate in the keystore (a keystore can hold multiple certificates). It has nothing to do with the server name, or the domain name of the Tomcat service.
- The **common name** (CN) is an attribute of the TLS certificate. Your browser will usually complain if the CN of the certificate and the domain in the URI do not match (but since you're using a self-signed certificate, your browser will probably complain anyway...). HOWEVER, when generating the certificate, the keytool will ask for "your first and last name" when asking for the CN, so keep that in mind. The rest of the attributes are not really that important

So let's generate a strong 4096-bit certificate that is valid for 2 years.

```sh
# adjust the path to `keytool`, ALIAS and the path to the keystore accordingly
./jdk1.8/bin/keytool -genkey -keystore /srv/jakarta/.keystore -alias ALIAS \
    -keyalg RSA -keysize 4096 -validity 720
Enter keystore password = # well, enter something
Re-enter new password = # same as above
What is your first and last name?
  [Unknown]:  example.com # !!! IMPORTANT this is the domain name, NOT YOUR name
What is the name of your organizational unit?
  [Unknown]:  # enter something or leave empty
What is the name of your organization?
  [Unknown]:  # enter something or leave empty
What is the name of your City or Locality?
  [Unknown]:  # enter something or leave empty
What is the name of your State or Province?
  [Unknown]:  # enter something or leave empty
What is the two-letter country code for this unit?
  [Unknown]:  # enter something or leave empty
Is CN=example com, OU=Foo, O=Bar, L=City, ST=AA, C=FB correct?
  [no]:  yes
Enter key password for <ALIAS>
    (RETURN if same as keystore password): # Press RETURN
```

Great, now the keystore has been created (if it didn't exist already) and your self-signed certificate has been added to it.

## Step 2: Configure Tomcat

To use the new certificate, configure your Tomcat accordingly:

Activate the HTTPS-Connector in your `conf/server.xml`. Adjust `keyAlias`, `keystoreFile` and `keystorePass` accordingly:

```xml
<Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
           maxThreads="150" SSLEnabled="true" scheme="https" secure="true"
           clientAuth="false" sslProtocol="TLS"
           keyAlias="ALIAS" keystoreFile="/srv/jakarta/.keystore"
           keystorePass="PW from step 1" />
```

And that's it! Restart Tomcat and you're ready!
