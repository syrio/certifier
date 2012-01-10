winston = require 'winston'


levels_options = 
  levels:
    inform: 0,
    debug: 1,
    ok: 2,
    notok: 3,
    error: 4
  colors:
    inform: 'blue'
    ok: 'green'
    notok: 'yellow'
    error: 'red',


console_options = 
  level: 'inform',
  silent: false,
  colorize: true,
  timestamp: true
  
console_transport = new winston.transports.Console console_options

logger_options = 
  transports: [console_transport]
  levels: levels_options.levels
  colors: levels_options.colors
    
exports.logger = new winston.Logger logger_options
