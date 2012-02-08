optimist = require 'optimist'
argv = optimist.argv
logger = require('./logger').logger

fs = require 'fs'
forge = require './forge/js/forge'
  


readCertificateOptionsFile = (path, cb) ->

  fs.readFile path, 'utf8', (err, raw_options) ->
    
    return cb err if err 
    
    try
      options = JSON.parse raw_options
    catch e
      cb e
    cb 0, options

loadCertificateFile = (path, cb) ->

  fs.readFile path, 'utf8', (err, pem) ->
    return cb err if err 
    
    try 
      cert = forge.pki.certificateFromPem pem, true
      cb 0, cert
    catch e
      cb e
    
saveCertificateToFile = (path, cert, cb) ->

  pem = forge.pki.certificateToPem cert
  
  fs.writeFile path, pem, 'utf8', (err) ->
    return cb err if err 
    cb 0


loadKeyFile = (path, cb) ->
  fs.readFile path, 'utf8', (err, pem) ->
    return cb err if err 
    try 
      key = forge.pki.privateKeyFromPem pem, true
      cb 0, key
    catch e
      cb e

generateCertificate = (options, issuer) ->
  
  cert = forge.pki.createCertificate()
  cert.serialNumber = options.serial
  
  cert.validity.notBefore = new Date(options.date.notBefore)
  cert.validity.notAfter = new Date(options.date.notAfter)
  
  attrs = [{
    name: 'commonName',
    value: options.common
  }, {
    name: 'countryName',
    value: options.country
  }, {
    shortName: 'ST',
    value: options.state
  }, {
    name: 'localityName',
    value: options.locality
  }, {
    name: 'organizationName',
    value: options.organization
  }, {
    shortName: 'OU',
    value: options.ou
  }]
  

  cert.setSubject(attrs)
  if issuer?
    cert.setIssuer issuer
  else
    cert.setIssuer(attrs)
    
  cert.setExtensions([{
    name: 'basicConstraints',
    cA: true
  }, {
    name: 'keyUsage',
    keyCertSign: true,
    digitalSignature: true,
    nonRepudiation: true,
    keyEncipherment: true,
    dataEncipherment: true
  }, {
    name: 'subjectAltName',
    altNames: [{
      type: options.subject.type, 
      value: options.subject.name
    }]
  }])

  
  cert.attrs = attrs
  
  cert
  

generateCaCertificate = (options) ->
  
  cert = generateCertificate options
  
  keys = forge.pki.rsa.generateKeyPair(1024)
  
  cert.publicKey = keys.publicKey

  cert.sign(keys.privateKey)

  pem = {
    privateKey: forge.pki.privateKeyToPem(keys.privateKey),
    publicKey: forge.pki.publicKeyToPem(keys.publicKey),
    certificate: forge.pki.certificateToPem(cert)
  }
  
  return { cert: cert, pem: pem, keys: keys }
  

generateClientCertificate = (options, ca) ->
  
  cert = generateCertificate options, ca.cert.attrs
  
  cert.publicKey = ca.keys.publicKey

  cert.sign(ca.keys.privateKey)
  
  return { cert: cert  }
  

verifyClientCertificate = (client, ca_cert, cb) ->
  
  store = forge.pki.createCaStore()
  
  store.addCertificate ca_cert
  
  try
    forge.pki.verifyCertificateChain store, [client], (verified, depth, chain) ->
      cb 0, verified
      return true
  catch ex
    logger.notok "Certificate verification process failed: \n #{JSON.stringify(ex)}"
    cb ex
      
 
verifyClientCertificateFile = (client_path, ca_path, cb) ->
  
  loadCertificateFile ca_path, (err, ca_cert) ->
    if err
      logger.notok "Error reading the CA certiifcate file: #{err}"
      return cb err
    
    loadCertificateFile client_path, (err, client_cert) ->
      if err
        logger.notok "Error reading the client certiifcate file: #{err}"
        return cb err
      
      verifyClientCertificate client_cert, ca_cert, (err, verified) ->
        return cb(err) if err
        cb 0, verified

createKeyFile = (key_path, key, cb) ->
  
  key_pem = forge.pki.privateKeyToPem key
  fs.writeFile key_path, key_pem, 'utf8', (err) ->
    return cb err
  
        
createCAFile = (out_path, conf_path, cb) ->
  
  logger.ok 'Creating CA Certificate file'
  
  readCertificateOptionsFile conf_path, (err, options) ->

    return cb(err) if err
    
    logger.ok 'About to generate certificate, this might take a while...'

    ca = generateCaCertificate options
    
    logger.ok 'Done generating!'

    saveCertificateToFile out_path, ca.cert, (err) ->
      return cb(err) if err  
      cb 0, ca
    

createClientFile = (out_path, conf_path, ca, cb) ->
  
  logger.ok 'Creating Client Certificate file'

  readCertificateOptionsFile conf_path, (err, options) ->
    return cb(err) if err

    client = generateClientCertificate options, ca
    
    saveCertificateToFile out_path, client.cert, (err) ->
      return cb(err) if err  
      cb 0, client
    

createCAClientCertificateFiles = (ca_details, client_details, key_details, cb) ->
  
  createCAFile ca_details.data_path, ca_details.conf_path, (err, ca) ->
    
    return cb(err) if err
    
    createKeyFile key_details.data_path, ca.keys.privateKey, (err) ->
      return cb(err) if err
    
      createClientFile client_details.data_path, client_details.conf_path, ca, (err, client) ->
        return cb(err) if err
      
        verifyClientCertificate client.cert, ca.cert, (err, verified) ->
          return cb(err) if err
        
          logger.ok "Is this verified? #{verified}"
            
          cb 0, {}
      

generateCertificates = (client, ca, key, cb) ->
  
  logger.ok 'Creating Certificate files'
  
  createCAClientCertificateFiles ca, client, key, (err, files) ->
    if err
      logger.notok "Error creating the CA and client certificates PEM files: #{err.message}\n #{err.stack}\n"
    else
      logger.ok "Created new CA and client certificates PEM files and a private key file!"
    cb()
    
  
signCertificate = (client_details, ca_details, key_details, cb) ->

    loadCertificateFile ca_details.data_path, (err, ca_cert) ->
      if err
        logger.notok "Error reading the CA certiifcate file: #{JSON.stringify(err)}"
        return cb err

      loadKeyFile key_details.data_path, (err, ca_private_key) ->

        if err
          logger.notok "Error reading the key file: #{err}"
          return cb err

        ca = {cert: ca_cert, keys: {privateKey: ca_private_key, publicKey: ca_cert.publicKey}}

        createClientFile client_details.data_path, client_details.conf_path, ca, (err, client) ->
          if err
            logger.notok "Error creating the client certiifcate file: #{err}"
            return cb err
          
          logger.ok "Created a new signed client certificate using given CA!"
          
          verifyClientCertificate client.cert, ca_cert, (err, verified) ->
            return cb(err) if err
            cb 0, verified

startCertifier = ->
  
  help = [
      "usage: certifier [options]",
      "",
      "Runs the certification generator/verifier",
      "",
      "options:",
      "  -g, --generate   Generate a CA and a client certificate signed by the generated CA",
      "  -v, --verify     Verifies a given client certificate using a given CA certificate",
      "  -s, --sign       Generate and sign a new client certificate using a given CA certificate"
      "  -a, --authority  Path of the CA PEM file (output if -g)",
      "  -c, --client     Path of the Client PEM file (output if -g)",
      "  -n, --confca     Path of the CA certificate configuration JSON file",  
      "  -l, --confclient Path of the Client certificate configuration JSON file",
      "  -k, --key        Path of the Private key for signing additional client certificates",
      "  -h, --help       You're staring at it",
  ].join('\n')

  if argv.h? or argv.help?
    return console.log help

  options =
    generate: argv.g ? argv.generate
    verify: argv.v ? argv.verify
    sign: argv.s ? argv.sign
    ca: 
      data_path: argv.a ? argv.authority
      conf_path: argv.n ? argv.confca
    client: 
      data_path: argv.c ? argv.client
      conf_path: argv.l ? argv.confclient
    key:
      data_path: argv.k ? argv.key
  
  if options.verify? and options.generate? and options.sign?
    return logger.notok "Error! You can either generate or verify certificates"
  
  unless options.ca.data_path? and options.client.data_path?
    return logger.notok "Must provide both a CA and a Client file path"
  
  if options.verify?
    verifyClientCertificateFile options.client.data_path, options.ca.data_path, (err, verified) ->
      return logger.error err if err
      if verified == true
        logger.ok 'Certificate IS verified by the given CA!'
      else
        logger.notok 'Certificate IS *NOT* verified by the given CA!'
  
  if options.generate?
    unless options.ca.conf_path? and options.client.conf_path? and options.key.data_path?
      return logger.notok "Must provide both an configuration file for CA and Client certificates and an output path for the generated signing key if you want to generate new certificates"
    return generateCertificates options.client, options.ca, options.key, () ->
      return
  
  if options.sign?
    unless options.ca.data_path? and options.client.conf_path? and options.client.data_path? and options.key.data_path?
      return logger.notok "Must provide both an configuration file for client, a CA certificate file and a signing key if you want to sign new certificates"
    return signCertificate options.client, options.ca, options.key, () ->
      return

startCertifier()