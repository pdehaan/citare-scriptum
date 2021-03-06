fs   = require 'fs'
path = require 'path'

_            = require 'underscore'
coffeeScript = require 'coffee-script'
fsTools      = require 'fs-tools'
jade         = require 'jade'
uglifyJs     = require 'uglify-js'
stylus       = require 'stylus'

Base = require './base'


module.exports = class Groc extends Base
  STATIC_ASSETS: []

  constructor: (args...) ->
    super(args...)

    @sourceAssets = path.join __dirname, 'groc'
    @targetAssets = path.resolve @project.outPath, 'assets'

    templateData  = fs.readFileSync path.join(@sourceAssets, 'docPage.jade'), 'utf-8'
    @templateFunc = jade.compile templateData

  renderCompleted: (callback) ->
    @log.trace 'styles.Groc#renderCompleted(...)'

    super (error) =>
      return error if error
      @copyAssets =>
        @compileScript =>
          @compileCss callback

  copyAssets: (callback) ->
    @log.trace 'styles.Groc#copyAssets(...)'

    # Even though fsTools.copy creates directories if they're missing - we want a bit more control
    # over it (permissions), as well as wanting to avoid contention.
    fsTools.mkdir @targetAssets, '0755', (error) =>
      if error
        @log.error 'Unable to create directory %s: %s', @targetAssets, error.message
        return callback error
      @log.trace 'mkdir: %s', @targetAssets

      numCopied = 0
      for asset in @STATIC_ASSETS
        do (asset) =>
          assetTarget = path.join @targetAssets, asset
          fsTools.copy path.join(@sourceAssets, asset), assetTarget, (error) =>
            if error
              @log.error 'Unable to copy %s: %s', assetTarget, error.message
              return callback error
            @log.trace 'Copied %s', assetTarget

            numCopied += 1
      callback()

  compileScript: (callback) ->
    @log.trace 'styles.Groc#compileScript(...)'

    scriptPath = path.join @sourceAssets, 'behavior.coffee'
    fs.readFile scriptPath, 'utf-8', (error, data) =>
      if error
        @log.error 'Failed to read %s: %s', scriptPath, error.message
        return callback error

      try
        scriptSource = _.template data, @
      catch error
        @log.error 'Failed to interpolate %s: %s', scriptPath, error.message
        return callback error

      try
        scriptSource = coffeeScript.compile scriptSource
        @log.trace 'Compiled %s', scriptPath
      catch error
        @log.debug scriptSource
        @log.error 'Failed to compile %s: %s', scriptPath, error.message
        return callback error

      @compressScript scriptSource, callback

  compressScript: (scriptSource, callback) ->
    @log.trace 'styles.Groc#compressScript(..., ...)'

    try
      compiledSource = uglifyJs.minify(scriptSource, {fromString: true, mangle: true, unsafe: true}).code

    catch error
      @log.error 'Failed to compress assets/behavior.js: %s', error.message
      return callback error

    @concatenateScripts compiledSource, callback

  concatenateScripts: (scriptSource, callback) ->
    @log.trace 'styles.Groc#concatenateScripts(..., ...)'

    jqueryPath = path.join @sourceAssets, 'jquery.min.js'
    fs.readFile jqueryPath, 'utf-8', (error, data) =>
      if error
        @log.error 'Failed to read %s: %s', jqueryPath, error.message
        return callback error

      outputPath = path.join @targetAssets, 'behavior.js'
      fs.writeFile outputPath, data + scriptSource, (error) =>
        if error
          @log.error 'Failed to write %s: %s', outputPath, error.message
          return callback error
        @log.trace 'Wrote %s', outputPath

        callback()

  compileCss: (callback) ->
    stylusPath = path.join @sourceAssets, 'style.styl'
    fs.readFile stylusPath, 'utf-8', (error, data) =>
      if error
        @log.error 'Failed to read %s: %s', stylusPath, error.message
        return callback error
      stylus(data).set("filename", stylusPath).set("compress", true)
        .define("url", stylus.url()).render (error, css) =>
          if error
            @log.error 'Failed to compile CSS %s: %s', stylusPath, error.message
            return callback error
          outputPath = path.join @targetAssets, 'style.css'
          fs.writeFile outputPath, css, (error) =>
            if error
              @log.error 'Failed to write %s: %s', outputPath, error.message
              return callback error
            @log.trace 'Wrote %s', outputPath
            callback()
