(function() {
  var DropHandler, FileHandler, StateManager;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  FileHandler = (function() {
    FileHandler.prototype.raw_ca = "-----BEGIN CERTIFICATE-----    MIICtDCCAh2gAwIBAgIBATANBgkqhkiG9w0BAQUFADB7MRQwEgYDVQQDEwtDZXJ0    aWZpZXJDQTELMAkGA1UEBhMCVVMxETAPBgNVBAgTCFZpcmdpbmlhMRMwEQYDVQQH    EwpXYXNoaW5ndG9uMRYwFAYDVQQKEw1DZXJ0aWZpZXJUZXN0MRYwFAYDVQQLEw1D    ZXJ0aWZpZXJUZXN0MB4XDTEyMDEwODEyMTAxN1oXDTEyMDIwODEyMTAxN1owezEU    MBIGA1UEAxMLQ2VydGlmaWVyQ0ExCzAJBgNVBAYTAlVTMREwDwYDVQQIEwhWaXJn    aW5pYTETMBEGA1UEBxMKV2FzaGluZ3RvbjEWMBQGA1UEChMNQ2VydGlmaWVyVGVz    dDEWMBQGA1UECxMNQ2VydGlmaWVyVGVzdDCBnzANBgkqhkiG9w0BAQEFAAOBjQAw    gYkCgYEAy5trNHpKx0h+WYzmDro2OzZdkMEc2+iXOcaDDU/ancg5AMePD9+1Oklo    jt4Mx5md5rqybLpv3S+G6D97qdVdWWWboEFvzsPCuCAQV5cq0aaGkR5lLkpZlklg    gT+bVR1L2FCMIUkUPjAydiuk0u/C9V9s9sH31veByPqJoJ5AnfECAwEAAaNIMEYw    DAYDVR0TBAUwAwEB/zALBgNVHQ8EBAMCAvQwKQYDVR0RBCIwIIYeaHR0cDovL2Nh    LkNlcnRpZmllci5vcmcvdWJlcmNhMA0GCSqGSIb3DQEBBQUAA4GBAAPm83M+FDbF    LuVjDbHqM+7/Q2hKw/9ILY/Cw5fi+vdcmRMCEh9vO5uyxxhkrC22xtUBuzUViUNl    2we6qZIeYHXVwkTrWuN3aT0MK2j6R/IcVetvAPyi9MJvdFkHyig8pZElV2yN5isv    26o6ZMZ3KfuMPJVcpikLINelJNSB1Led    -----END CERTIFICATE-----";
    function FileHandler(file, cb) {
      var ca, reader;
      ca = forge.pki.certificateFromPem(this.raw_ca, true);
      this.store = forge.pki.createCaStore();
      this.store.addCertificate(ca);
      reader = new FileReader;
      reader.onloadend = __bind(function(evt) {
        var cert;
        try {
          cert = forge.pki.certificateFromPem(evt.target.result, true);
        } catch (ex) {
          $('#fileDetails').text("Failed to verify certificate!");
          $('#error').text("" + ex);
        }
        if (cert == null) {
          return;
        }
        if (evt.target.readyState === FileReader.DONE) {
          this.verifyCertificate(cert, cb);
          return false;
        }
      }, this);
      reader.readAsText(file);
    }
    FileHandler.prototype.verifyCertificate = function(cert, cb) {
      try {
        return forge.pki.verifyCertificateChain(this.store, [cert], function(verified, depth, chain) {
          cb(0, verified);
          return true;
        });
      } catch (ex) {
        console.log("Certificate verification process failed: \n " + (JSON.stringify(ex)));
        return cb(ex);
      }
    };
    return FileHandler;
  })();
  DropHandler = (function() {
    function DropHandler(element, cb) {
      this.cb = cb;
      this.onDrop = __bind(this.onDrop, this);
      element.addEventListener('drop', this.onDrop, false);
      element.addEventListener('dragenter', this.handleOnOurOwn, false);
      element.addEventListener('dragover', this.handleOnOurOwn, false);
      element.addEventListener('dragleave', this.handleOnOurOwn, false);
    }
    DropHandler.prototype.handleOnOurOwn = function(evt) {
      evt.stopPropagation();
      return evt.preventDefault();
    };
    DropHandler.prototype.onDrop = function(evt) {
      var file, handler;
      this.handleOnOurOwn(evt);
      file = evt.dataTransfer.files[0];
      $('#verifyResults').text('');
      console.log("A new certificate named " + file.name + " that is " + file.size + " bytes in size was dropped!");
      $('#fileDetails').text("A new certificate named " + file.name + " that is " + file.size + " bytes in size was dropped!");
      return handler = new FileHandler(file, this.cb);
    };
    return DropHandler;
  })();
  StateManager = (function() {
    function StateManager() {
      this.browserSupportsPrerequisites();
      this.initializeStoredState();
    }
    StateManager.prototype.browserSupportsPrerequisites = function() {
      if (window.localStorage == null) {
        throw {
          error: 'Cert.State.NoBrowserSupport',
          message: 'Browser doesnt support HTML5 localStorage'
        };
      }
    };
    StateManager.prototype.initializeStoredState = function() {
      if ((localStorage.first_use_date != null) && !(localStorage.last_use_date != null)) {
        throw {
          error: 'Cert.State.MalformedState',
          message: 'Malformed state: only part of the stored state exists in storage'
        };
      } else if (!((localStorage.first_use_date != null) && (localStorage.last_use_date != null))) {
        localStorage.first_use_date = new Date();
        return localStorage.last_use_date = new Date();
      } else if ((localStorage.first_use_date != null) && (localStorage.last_use_date != null)) {
        return localStorage.last_use_date = new Date();
      }
    };
    return StateManager;
  })();
  window.onload = function() {
    var element, verifyCerificate;
    verifyCerificate = function(element, cb) {
      var state_manager;
      try {
        state_manager = new StateManager;
      } catch (ex) {
        cb(ex);
      }
      return new DropHandler(element, cb);
    };
    element = document.getElementById('playingField');
    return verifyCerificate(element, function(err, verified) {
      if (err) {
        $('#fileDetails').text("Failed to verify certificate!");
      }
      if (verified === true) {
        return $('#fileDetails').text("Ceritifcate verified!");
      } else {
        return $('#fileDetails').text("Bad certificate!");
      }
    });
  };
}).call(this);
