
class FileHandler
  
  raw_ca : 
    "-----BEGIN CERTIFICATE-----
    MIICtDCCAh2gAwIBAgIBATANBgkqhkiG9w0BAQUFADB7MRQwEgYDVQQDEwtDZXJ0
    aWZpZXJDQTELMAkGA1UEBhMCVVMxETAPBgNVBAgTCFZpcmdpbmlhMRMwEQYDVQQH
    EwpXYXNoaW5ndG9uMRYwFAYDVQQKEw1DZXJ0aWZpZXJUZXN0MRYwFAYDVQQLEw1D
    ZXJ0aWZpZXJUZXN0MB4XDTEyMDEwODEyMTAxN1oXDTEyMDIwODEyMTAxN1owezEU
    MBIGA1UEAxMLQ2VydGlmaWVyQ0ExCzAJBgNVBAYTAlVTMREwDwYDVQQIEwhWaXJn
    aW5pYTETMBEGA1UEBxMKV2FzaGluZ3RvbjEWMBQGA1UEChMNQ2VydGlmaWVyVGVz
    dDEWMBQGA1UECxMNQ2VydGlmaWVyVGVzdDCBnzANBgkqhkiG9w0BAQEFAAOBjQAw
    gYkCgYEAy5trNHpKx0h+WYzmDro2OzZdkMEc2+iXOcaDDU/ancg5AMePD9+1Oklo
    jt4Mx5md5rqybLpv3S+G6D97qdVdWWWboEFvzsPCuCAQV5cq0aaGkR5lLkpZlklg
    gT+bVR1L2FCMIUkUPjAydiuk0u/C9V9s9sH31veByPqJoJ5AnfECAwEAAaNIMEYw
    DAYDVR0TBAUwAwEB/zALBgNVHQ8EBAMCAvQwKQYDVR0RBCIwIIYeaHR0cDovL2Nh
    LkNlcnRpZmllci5vcmcvdWJlcmNhMA0GCSqGSIb3DQEBBQUAA4GBAAPm83M+FDbF
    LuVjDbHqM+7/Q2hKw/9ILY/Cw5fi+vdcmRMCEh9vO5uyxxhkrC22xtUBuzUViUNl
    2we6qZIeYHXVwkTrWuN3aT0MK2j6R/IcVetvAPyi9MJvdFkHyig8pZElV2yN5isv
    26o6ZMZ3KfuMPJVcpikLINelJNSB1Led
    -----END CERTIFICATE-----"

  constructor: (file, cb) ->

    ca = forge.pki.certificateFromPem @raw_ca, true
    
    @store = forge.pki.createCaStore()
    
    @store.addCertificate ca
    
    reader = new FileReader

    # If we use onloadend, we need to check the readyState.
    reader.onloadend = (evt) =>
      
      try
        cert = forge.pki.certificateFromPem evt.target.result, true
      catch ex
        $('#fileDetails').text "Failed to verify certificate!"
        $('#error').text "#{ex}"
      
      return unless cert?
      
      if evt.target.readyState == FileReader.DONE
        
        @verifyCertificate cert, cb

        return false


    reader.readAsText(file)

  verifyCertificate: (cert, cb) ->
    
    try
      forge.pki.verifyCertificateChain @store, [cert], (verified, depth, chain) ->
        if verified
          localStorage.first_use_date = new Date()
          localStorage.last_use_date = new Date()
          localStorage.not_after = cert.validity.notAfter
          localStorage.not_before = cert.validity.notBefore
        
        cb 0, verified
        return true
    catch ex
      console.log "Certificate verification process failed: \n #{JSON.stringify(ex)}"
      cb ex


class DropHandler

  constructor: (element, @cb) ->

    element.addEventListener 'drop', @onDrop, false
    # disable the default browser's drop behavior by implementing these related events
    element.addEventListener 'dragenter', @handleOnOurOwn, false
    element.addEventListener 'dragover', @handleOnOurOwn, false
    element.addEventListener 'dragleave', @handleOnOurOwn, false


  handleOnOurOwn: (evt) ->
    evt.stopPropagation()
    evt.preventDefault()

  onDrop: (evt) =>

    @handleOnOurOwn(evt)
    
    # take the first file
    file = evt.dataTransfer.files[0]
    
    # Clear any previously handled file results
    $('#verifyResults').text ''
    
    console.log "A new certificate named #{file.name} that is #{file.size} bytes in size was dropped!"
    $('#fileDetails').text "A new certificate named #{file.name} that is #{file.size} bytes in size was dropped!"

    handler = new FileHandler(file, @cb)


class LicenseManager
  
  constructor: (cb) ->
    
    try
     
      unless @stateExists()
        return cb {error: 'Cert.State.NotExisting', message: 'Certificate hasnt been supplied by user in the past so cannot check license'}
    
      if @licenseValid()
        @updateUsage()
        cb 0, true
      else
        console.log "License invalid"
        cb 0, false
        
    catch ex
      cb ex
      
  licenseValid: ->
    now = new Date()

    if now < new Date(localStorage.last_use_date) or now < new Date(localStorage.first_use_date) or now < new Date(localStorage.not_before)
      throw {error: 'Cert.State.DateTempering', message: 'Inconsistency in clocks, user date has been changed to the past'}
      
    now < new Date(localStorage.not_after)
  
  updateUsage: ->
    now = new Date()    
    localStorage.last_use_date = now
    
  stateExists: ->
    one_does = localStorage.first_use_date? or localStorage.last_use_date? or localStorage.not_before? or localStorage.not_after?
    another_doesnt = not localStorage.first_use_date? or not localStorage.last_use_date? or not localStorage.not_before? or not localStorage.not_after?
    
    if one_does and another_doesnt
      throw {error: 'Cert.State.MalformedState', message: 'Malformed state: only part of the stored state exists in storage'}
      
    if another_doesnt
      # there's no state, initialize it
      return false
    else  
      return true
  
        
    

window.onload = ->
  
  browserSupportsPrerequisites = ->
    #! Change this to use the Modernizr script (modernizr.com)
    # Check for HTML5 localStorage support
    # Check for HTML5 File API support
    window.localStorage? and winodw.FileReader?
    
  
  verifyUsage = (cb) ->
    license_manager = new LicenseManager cb
  
  verifyCerificate = (element, cb) ->  
    new DropHandler element, cb

  unless browserSupportsPrerequisites()
    $('#error').text "Cannot work on this browser"
  
  verifyUsage (err, verified) ->
    # example cb
    console.log "Err: #{JSON.stringify err}, Verified: #{verified}"
  
  element = document.getElementById 'playingField'
  verifyCerificate element, (err, verified) ->
    # example cb
    if err
      $('#fileDetails').text "Failed to verify certificate!"
    if verified == true
      $('#fileDetails').text "Ceritifcate verified!"
    else
      $('#fileDetails').text "Bad certificate!"
  
    
    