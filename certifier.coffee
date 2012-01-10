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
      cb 0, options
    catch e
      cb e
  

loadCertificateFile = (path, cb) ->

  fs.readFile path, 'utf8', (err, data) ->
    return cb err if err 
    
    try 
      cert = forge.pki.certificateFromPem data, true
      cb 0, cert
    catch e
      cb e
    
saveCertificateToFile = (path, cert, cb) ->
  
  pem = forge.pki.certificateToPem cert
  
  fs.writeFile path, pem, 'utf8', (err) ->
    return cb err if err 
    cb 0

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
  

verifyClientCertificate = (client, ca, cb) ->
  
  store = forge.pki.createCaStore()
  
  store.addCertificate ca
  
  try
    forge.pki.verifyCertificateChain store, [client], (verified, depth, chain) ->
      cb 0, verified
      return true
  catch ex
    console.log "Certificate verification process failed: \n #{JSON.stringify(ex)}"
    #cb ex
      
 
verifyClientCertificateFile = (client_path, ca_path, cb) ->
  
  loadCertificateFile ca_path, (err, ca_cert) ->
    if err
      return console.log "Error reading the CA certiifcate file: #{err}"
    
    loadCertificateFile client_path, (err, client_cert) ->
      if err
        console.log "Error reading the client certiifcate file: #{err}"
        return cb err
      
      verifyClientCertificate client_cert, ca_cert, (err, verified) ->
        return cb(err) if err
        cb 0, verified
        
createCAFile = (out_path, conf_path, cb) ->
  
  console.log 'Creating CA Certificate file'
  
  readCertificateOptionsFile conf_path, (err, options) ->
    return cb(err) if err
  
    ca = generateCaCertificate options

    saveCertificateToFile out_path, ca.cert, (err) ->
      return cb(err) if err  
      cb 0, ca
    

createClientFile = (out_path, conf_path, ca, cb) ->
  
  console.log 'Creating Client Certificate file'

  readCertificateOptionsFile conf_path, (err, options) ->
    return cb(err) if err

    client = generateClientCertificate options, ca
    
    saveCertificateToFile out_path, client.cert, (err) ->
      return cb(err) if err  
      cb 0, client
    

createCAClientCertificateFiles = (ca_details, client_details, cb) ->
  
  createCAFile ca_details.output_path, ca_details.conf_path, (err, ca) ->
    
    return cb(err) if err
    
    createClientFile client_details.output_path, client_details.conf_path, ca, (err, client) ->
      return cb(err) if err
      
      verifyClientCertificate client.cert, ca.cert, (err, verified) ->
        return cb(err) if err
        
        console.log "Is this verified? #{verified}"
            
        cb 0, {}
      

generateCertificates = (client, ca) ->
  
  console.log 'Creating Certificate files'
  
  createCAClientCertificateFiles ca, client, (err, files) ->
    if err
      console.log "Error creating the CA and client certificates PEM files: #{err.message}\n #{err.stack}\n"
    else
      console.log "Created CA and client certificates PEM files"
  


startCertifier = ->
  
  help = [
      "usage: certifier [options]",
      "",
      "Runs the certification generator/verifier",
      "",
      "options:",
      "  -g, --generate   Generate a CA and a client certificate signed by the generated CA",
      "  -v, --verify     Verifies a given client certificate using a given CA certificate",
      "  -a, --authority  Path of the CA PEM file (output if -g)",
      "  -c, --client     Path of the Client PEM file (output if -g)",
      "  -n, --confca     Path of the CA certificate configuration JSON file",  
      "  -l, --confclient Path of the Client certificate configuration JSON file",          
      "  -h, --help       You're staring at it",
  ].join('\n')

  if argv.h? or argv.help?
    return console.log help

  options =
    generate: argv.g ? argv.generate
    verify: argv.v ? argv.verify
    ca: 
      output_path: argv.a ? argv.authority
      conf_path: argv.n ? argv.confca
    client: 
      output_path: argv.c ? argv.client
      conf_path: argv.l ? argv.confclient
  
  
  if options.verify? and options.generate?
    return console.log "Error! You can either generate or verify certificates"
  
  unless options.ca.output_path? and options.client.output_path?
    return console.log "Must provide both a CA and a Client file path"
  
  if options.verify?
    verifyClientCertificateFile options.client.output_path, options.ca.output_path, (err, verified) ->
      return logger.error err if err
      if verified == true
        logger.ok 'Certificate IS verified by the given CA!'
      else
        logger.notok 'Certificate IS *NOT* verified by the given CA!'
  
  if options.generate?
    unless options.ca.conf_path? and options.client.conf_path?
      return console.log "Must provide both an configuration file for CA and Client certificates if you want to generate new certificates"
    return generateCertificates options.client, options.ca
    

startCertifier()