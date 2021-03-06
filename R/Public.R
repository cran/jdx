# Standard Interface ------------------------------------------------------

# Most developers should use the standard interface.

#' @export
convertToJava <- function(value, length.one.vector.as.array = FALSE, scalars.as.objects = FALSE, array.order = "row-major", data.frame.row.major = TRUE, coerce.factors = TRUE) {

  # array.order is validated later.
  if (!is.logical(length.one.vector.as.array) || length(length.one.vector.as.array) != 1)
    stop("The parameter 'length.one.vector.as.array' requires a length-one logical vector.")
  if (!is.logical(scalars.as.objects) || length(scalars.as.objects) != 1)
    stop("The parameter 'scalars.as.objects' requires a length-one logical vector.")
  if (!is.logical(data.frame.row.major) || length(data.frame.row.major) != 1)
    stop("The parameter 'data.frame.row.major' requires a length-one logical vector.")
  if (!is.logical(coerce.factors) || length(coerce.factors) != 1)
    stop("The parameter 'coerce.factors' requires a length-one logical vector.")

  # The class AsIs (set via the function I()) can be used to indicate that
  # length one vectors/arrays/factors should be converted to arrays, not
  # scalars. It is ignored for all other structures.
  value.is.as.is <- inherits(value, "AsIs")
  length.one.vector.as.array <- length.one.vector.as.array || value.is.as.is

  # IMPORTANT: is.vector() returns TRUE for lists. I override this behavior
  # here.
  value.is.list <- is.list(value)
  value.is.vector <- is.vector(value) && !value.is.list

  # IMPORTANT: is.vector() returns FALSE for vectors of class AsIs. This code
  # overrides this behavior. `is.atomic()` is FALSE for all but vectors, arrays,
  # and factors. `is.null(dim(value))` is TRUE for both vectors *and* factors.
  # Hence, the final check is required: `!is.factor(value)`
  if (!value.is.vector && value.is.as.is)
    value.is.vector <- is.atomic(value) && is.null(dim(value)) && !is.factor(value)

  if (value.is.vector) {
    if (is.logical(value)) {
      value <- coerceLogicalNaValues(value)
    } else if (is.complex(value)) {
      throwUnsupportedRtypeException("complex")
    }
    if (length(value) != 1 || length.one.vector.as.array)
      return(rJava::.jarray(value))
    # At this point, we know to create a scalar.
    if (!scalars.as.objects) {
      # From the rJava::.jbyte documentation: ".jbyte is used when a scalar byte
      # is to be passed to Java." In other words, a raw vector of length
      # one will not be interpreted as a scalar byte value by rJava unless it is
      # wrapped in a special class. This will be non-intuitive for the user when
      # length.one.vector.as.array = FALSE and scalars.as.objects = FALSE because
      # the returned value will not be the same as the value passed in, yet it is
      # not a Java object; it is an R object wrapped in a custom class. By contrast,
      # when length.one.vector.as.array = FALSE and scalars.as.objects = TRUE, the
      # returned value is a reference to a java.lang.Byte object.
      if (is.raw(value))
        return(rJava::.jbyte(value))
      return(value)
    }
    # The Java documentation suggests using the 'valueOf' static method instead
    # of creating new instances for performance reasons. But .jcall() is slower
    # than .jnew() in this case.
    if (is.double(value))
      return(rJava::.jnew("java/lang/Double", value, check = FALSE))
    if (is.integer(value))
      return(rJava::.jnew("java/lang/Integer", value, check = FALSE))
    if (is.character(value)) {
      # rJava treats scalar NA_character_ as null. It assigns the other NA_*
      # types a reserved numeric value.
      if (is.na(value))
        return(rJava::.jnull())
      return(rJava::.jnew("java/lang/String", value, check = FALSE))
    }
    if (is.logical(value))
      return(rJava::.jnew("java/lang/Boolean", value, check = FALSE))
    if (is.raw(value))
      return(rJava::.jnew("java/lang/Byte", rJava::.jbyte(value), check = FALSE))
    throwUnsupportedRtypeException(class(value))
  }

  if (is.array(value)) {
    if (is.logical(value)) {
      value <- coerceLogicalNaValues(value)
    } else if (is.complex(value)) {
      throwUnsupportedRtypeException("complex")
    }
    if (length(dim(value)) == 1)
      return(convertToJava(as.vector(value), length.one.vector.as.array = length.one.vector.as.array, scalars.as.objects = scalars.as.objects))
    if (array.order == "row-major")
      return(
        rJava::.jcall(
          jdx.utility
          , "Ljava/lang/Object;"
          , "createNdimensionalArrayRowMajor"
          , rJava::.jarray(value, dispatch = FALSE)
          , dim(value)
          , check = TRUE
        )
      )
    if (array.order == "column-major")
      return(
        rJava::.jcall(
          jdx.utility
          , "Ljava/lang/Object;"
          , "createNdimensionalArrayColumnMajor"
          , rJava::.jarray(value, dispatch = FALSE)
          , rev(dim(value))
          , check = TRUE
        )
      )
    if (array.order == "column-minor") {
      dimensions <- rev(dim(value))
      dimensions.length <- length(dimensions)
      # Swap row/column dimensions
      row.count <- dimensions[dimensions.length]
      dimensions[dimensions.length] <- dimensions[dimensions.length - 1]
      dimensions[dimensions.length - 1] <- row.count
      return(
        rJava::.jcall(
          jdx.utility
          , "Ljava/lang/Object;"
          , "createNdimensionalArrayColumnMinor"
          , rJava::.jarray(value, dispatch = FALSE)
          , dimensions
          , check = TRUE
        )
      )
    }
    stop(sprintf("Invalid 'array.order' parameter: '%s'.", array.order))
  }

  if (is.factor(value)) {
    if (coerce.factors)
      return(convertToJava(coerceFactor(value), length.one.vector.as.array = length.one.vector.as.array, scalars.as.objects = scalars.as.objects))
    return(convertToJava(as.character(value), length.one.vector.as.array = length.one.vector.as.array, scalars.as.objects = scalars.as.objects))
  }

  if (is.null(value))
    return(rJava::.jnull())

  if (is.data.frame(value)) {
    names <- names(value)
    if (is.null(names)) # It is possible to set names(data.frame) to NULL
      names <- character()
    if (ncol(value)) {
      validateNames(names)
    }
    # Notice that length.one.vector.as.array = TRUE here. Hence, the setting for scalars.as.objects is irrelevant.
    if (data.frame.row.major)
      return(
        rJava::.jcall(
          jdx.utility
          , "Ljava/util/List;"
          , "createListOfRecords"
          , rJava::.jarray(names)
          , rJava::.jarray(lapply(value, convertToJava, length.one.vector.as.array = TRUE, coerce.factors = coerce.factors))
          , check = TRUE
        )
      )
    return(
      rJava::.jcall(
        jdx.utility
        , "Ljava/util/Map;"
        , "createMap"
        , rJava::.jarray(names)
        , rJava::.jarray(lapply(value, convertToJava, length.one.vector.as.array = TRUE, coerce.factors = coerce.factors))
        , check = FALSE
      )
    )
  }

  # Always place after test for data frame because is.list() will return TRUE for data frames.
  if (value.is.list || is.environment(value)) {
    # Catch POSIXlt/POSIXt. They can be detected as lists.
    if (inherits(value, "POSIXlt"))
      throwUnsupportedRtypeException("POSIXlt")
    names <- names(value)
    if (length(value)) {
      if (!is.null(names)) # names will be NULL for unnamed lists.
        validateNames(names)
    }
    if (is.null(names))
      return(
        rJava::.jcall(
          jdx.utility
          , "Ljava/util/List;"
          , "createList"
          , rJava::.jarray(lapply(value, convertToJava, length.one.vector.as.array = length.one.vector.as.array, scalars.as.objects = TRUE, array.order = array.order, data.frame.row.major = data.frame.row.major, coerce.factors = coerce.factors))
          , check = FALSE
        )
      )
    return(
      rJava::.jcall(
        jdx.utility
        , "Ljava/util/Map;"
        , "createMap"
        , rJava::.jarray(names(value))
        , rJava::.jarray(lapply(value, convertToJava, length.one.vector.as.array = length.one.vector.as.array, scalars.as.objects = TRUE, array.order = array.order, data.frame.row.major = data.frame.row.major, coerce.factors = coerce.factors))
        , check = FALSE
      )
    )
  }

  throwUnsupportedRtypeException(class(value))
}

# The Java code for convertToR is contained in the class 
# org.fgilbert.jdx.JavaToR. The jdx.j2r variable is bound to a an instance of 
# this class that is re-used to improve performance. Recreating instances of 
# JavaToR is very expensive via rJava. Unfortunately, this performance comes as 
# the cost of thread-safety. Do not call convertToR from separate threads. Use 
# convertToRlowLevel for thread-safe object conversion. See documentation for 
# convertToRlowLevel.
#' @export
convertToR <- function(value, strings.as.factors = NULL, array.order = "row-major") {
  # strings.as.factors is validated in convertToRlowLevel()
  array.order.value <- array.order.values[[array.order]]
  if (is.null(array.order.value))
    stop(sprintf("Invalid 'array.order' parameter: '%s'.", array.order))
  composite.data.code <- rJava::.jcall(
    jdx.j2r
    , "I"
    , "initialize"
    , rJava::.jcast(value, new.class = "java/lang/Object", check = FALSE, convert.array = FALSE)
    , array.order.value
  )
  data.code <- processCompositeDataCode(jdx.j2r, composite.data.code)
  convertToRlowLevel(jdx.j2r, data.code, strings.as.factors)
}

#' @export
getJavaClassName <- function(value) {
  rJava::.jcall(rJava::.jcall(value, "Ljava/lang/Class;", "getClass"), "S", "getName")
}

# ConvertToR Low-level Interface ------------------------------------------

# These functions are used by the high-level interface. They can also be used in
# Java integrations (such as the jsr223 project) to avoid expensive rJava calls
# during conversion that create new objects or obtain references to objects.

#' @export
arrayOrderToString <- function(value) {
  if (rJava::.jequals(value, array.order.values$`row-major`))
    return("row-major")
  if (rJava::.jequals(value, array.order.values$`column-major`))
    return("column-major")
  if (rJava::.jequals(value, array.order.values$`column-minor`))
    return("column-minor")
  NULL
}

# IMPORTANT: Any logic added to convertToRlowLevel must usually be repeated in
# the nested function createList.
#' @export
convertToRlowLevel <- function(j2r, data.code = NULL, strings.as.factors = NULL) {

  createDataFrame <- function(x) {

    evalArray <- function(i) {
      return(rJava::.jevalArray(arrays[[i]], rawJNIRefSignature = dataCodeToJNI(processCompositeDataCode(j2r, types[i]))))
    }

    types <- rJava::.jevalArray(x[[1]], rawJNIRefSignature = "[I")
    if (length(types) == 0)
      return(data.frame())
    arrays <- rJava::.jevalArray(x[[2]], rawJNIRefSignature = "[Ljava/lang/Object;")
    df <- data.frame(
      lapply(1:(length(types)), evalArray)
      , stringsAsFactors = ifelse(is.null(strings.as.factors), defaultStringsAsFactorsCompatibility(), strings.as.factors)
      , check.names = FALSE
      , fix.empty.names = FALSE
    )
    names(df) <- rJava::.jevalArray(x[[3]], rawJNIRefSignature = "[Ljava/lang/String;")
    return(df)
  }

  createList <- function(x, data.code) {

    evalObject <- function(i) {

      data.code <- processCompositeDataCode(j2r, types[i])

      if (data.code[1] == TC_NULL)
        return(NULL)

      if (data.code[2] == SC_SCALAR) {
        if (data.code[1] == TC_RAW)
          return(as.raw(bitwAnd(rJava::.jsimplify(objects[[i]]), 0xff)))
        return(rJava::.jsimplify(objects[[i]]))
      }

      if (data.code[2] == SC_VECTOR)
        return(rJava::.jevalArray(objects[[i]], rawJNIRefSignature = dataCodeToJNI(data.code)))

      if (data.code[2] == SC_ND_ARRAY)
        return(createNdimensionalArray(rJava::.jevalArray(objects[[i]], rawJNIRefSignature = "[Ljava/lang/Object;"), data.code))

      if (data.code[2] == SC_DATA_FRAME)
        return(createDataFrame(rJava::.jevalArray(objects[[i]], rawJNIRefSignature = "[Ljava/lang/Object;")))

      if (data.code[2] == SC_LIST || data.code[2] == SC_NAMED_LIST)
        return(createList(rJava::.jevalArray(objects[[i]], rawJNIRefSignature = "[Ljava/lang/Object;"), data.code))

      throwUnsupportedDataCodeException(data.code)
    }

    types <- rJava::.jevalArray(x[[1]], rawJNIRefSignature = "[I")
    if (length(types) == 0)
      return(list())
    objects <- rJava::.jevalArray(x[[2]], rawJNIRefSignature = "[Ljava/lang/Object;")
    lst <- lapply(1:(length(types)), evalObject)
    if (data.code[2] == SC_NAMED_LIST)
      names(lst) <- rJava::.jevalArray(x[[3]], rawJNIRefSignature = "[Ljava/lang/String;")
    return(lst)
  }

  createNdimensionalArray <- function(x, data.code) {
    dimensions <- rJava::.jevalArray(x[[1]], rawJNIRefSignature = "[I")
    # Providing `rawJNIRefSignature` is about 1/3 times faster than not.
    if (data.code[1] == TC_NUMERIC)
      return(array(rJava::.jevalArray(x[[2]], "[D"), dimensions))
    if (data.code[1] == TC_INTEGER)
      return(array(rJava::.jevalArray(x[[2]], "[I"), dimensions))
    if (data.code[1] == TC_CHARACTER)
      return(array(rJava::.jevalArray(x[[2]], "[Ljava/lang/String;"), dimensions))
    if (data.code[1] == TC_LOGICAL)
      return(array(rJava::.jevalArray(x[[2]], "[Z"), dimensions))
    if (data.code[1] == TC_RAW) {
      return(array(rJava::.jevalArray(x[[2]], "[B"), dimensions))
    }
    throwUnsupportedDataCodeException(data.code)
  }

  if (!is.null(strings.as.factors)) {
    if (!is.logical(strings.as.factors) || length(strings.as.factors) != 1)
      stop("The parameter 'strings.as.factors' requires a length-one logical vector or NULL.")
  }

  # If a data.code is not provided, retrieve and process it.
  if (is.null(data.code)) {
    composite.data.code <- rJava::.jcall(j2r, "I", "getRdataCompositeCode")
    data.code <- processCompositeDataCode(j2r, composite.data.code)
  }

  if (data.code[1] == TC_NULL)
    return(NULL)

  if (data.code[2] == SC_SCALAR) {
    if (data.code[1] == TC_NUMERIC)
      return(rJava::.jcall(j2r, "D", "getValueDouble", check = FALSE))
    if (data.code[1] == TC_INTEGER)
      return(rJava::.jcall(j2r, "I", "getValueInt", check = FALSE))
    if (data.code[1] == TC_CHARACTER)
      return(rJava::.jcall(j2r, "S", "getValueString", check = FALSE))
    if (data.code[1] == TC_LOGICAL)
      return(rJava::.jcall(j2r, "Z", "getValueBoolean", check = FALSE))
    if (data.code[1] == TC_RAW) {
      # Convert to raw manually. Unfortunately, rJava returns an integer vector
      # in this scenario. This is understandable because Java bytes range from
      # -128 to 127 whereas R raw values range from 0 to 255. However, this
      # behavior is inconsistent because rJava converts byte arrays to raw
      # values without hesitation and bitwise. So Java -1 maps to R 0xff. So,
      # that leaves me in a quandry. I have decided to make the behavior between
      # the scalars and the arrays consistent.
      return(as.raw(bitwAnd(rJava::.jcall(j2r, "B", "getValueByte", check = FALSE), 0xff)))
    }
    throwUnsupportedDataCodeException(data.code)
  }

  if (data.code[2] == SC_VECTOR) {
    if (data.code[1] == TC_NUMERIC)
      return(rJava::.jcall(j2r, "[D", "getValueDoubleArray1d", check = FALSE))
    if (data.code[1] == TC_INTEGER)
      return(rJava::.jcall(j2r, "[I", "getValueIntArray1d", check = FALSE))
    if (data.code[1] == TC_CHARACTER)
      return(rJava::.jcall(j2r, "[Ljava/lang/String;", "getValueStringArray1d", check = FALSE))
    if (data.code[1] == TC_LOGICAL)
      return(rJava::.jcall(j2r, "[Z", "getValueBooleanArray1d", check = FALSE))
    if (data.code[1] == TC_RAW)
      return(rJava::.jcall(j2r, "[B", "getValueByteArray1d", check = FALSE))
    throwUnsupportedDataCodeException(data.code)
  }

  if (data.code[2] == SC_ND_ARRAY)
    return(createNdimensionalArray(rJava::.jcall(j2r, "[Ljava/lang/Object;", "getValueObjectArray1d", check = FALSE), data.code))

  if (data.code[2] == SC_DATA_FRAME)
    return(createDataFrame(rJava::.jcall(j2r, "[Ljava/lang/Object;", "getValueObjectArray1d", check = FALSE)))

  if (data.code[2] == SC_LIST || data.code[2] == SC_NAMED_LIST)
    return(createList(rJava::.jcall(j2r, "[Ljava/lang/Object;", "getValueObjectArray1d", check = FALSE), data.code))

  throwUnsupportedDataCodeException(data.code)
}

#' @export
createJavaToRobject <- function() {
  rJava::.jnew("org/fgilbert/jdx/JavaToR")
}

#' @export
jdxConstants <- function() {
  list(
    ARRAY_ORDER = array.order.values

    , EC_NONE = EC_NONE
    , EC_EXCEPTION = EC_EXCEPTION
    , EC_WARNING_MISSING_LOGICAL_VALUES = EC_WARNING_MISSING_LOGICAL_VALUES
    , EC_WARNING_MISSING_RAW_VALUES = EC_WARNING_MISSING_RAW_VALUES

    , MSG_WARNING_MISSING_LOGICAL_VALUES = MSG_WARNING_MISSING_LOGICAL_VALUES
    , MSG_WARNING_MISSING_RAW_VALUES = MSG_WARNING_MISSING_RAW_VALUES

    , NA_ASSUMPTION_LOGICAL = NA_ASSUMPTION_LOGICAL
    , NA_ASSUMPTION_RAW = NA_ASSUMPTION_RAW

    , SC_SCALAR = SC_SCALAR
    , SC_VECTOR = SC_VECTOR
    # , SC_MATRIX = SC_MATRIX
    , SC_ND_ARRAY = SC_ND_ARRAY
    , SC_DATA_FRAME = SC_DATA_FRAME
    , SC_LIST = SC_LIST
    , SC_NAMED_LIST = SC_NAMED_LIST
    , SC_USER_DEFINED = SC_USER_DEFINED

    , TC_NULL = TC_NULL
    , TC_NUMERIC = TC_NUMERIC
    , TC_INTEGER = TC_INTEGER
    , TC_CHARACTER = TC_CHARACTER
    , TC_LOGICAL = TC_LOGICAL
    , TC_RAW = TC_RAW
    , TC_OTHER = TC_OTHER
    , TC_UNSUPPORTED = TC_UNSUPPORTED
  )
}

# IMPORTANT: This function throws warnings! If a warning handler is in
# place, execution will be interrupted when a warning is propagated.
#' @export
processCompositeDataCode <- function(j2r, composite.data.code, throw.exceptions = TRUE, warn.missing.logical = TRUE, warn.missing.raw = TRUE) {
  result <- c(
    bitwAnd(composite.data.code, 0xFFL)          # Data type code
    , bitwAnd(composite.data.code, 0xFF00L)      # Data structure code
    , bitwAnd(composite.data.code, 0xFF0000L)    # Exception code
    , bitwAnd(composite.data.code, 0x7F000000L)  # User defined code. Note that 0xFF000000 is a numeric (i.e., double) in R.
  )
  if (result[3] == EC_NONE) {
    # Do nothing
  } else if (result[3] == EC_EXCEPTION && throw.exceptions) {
    stop(rJava::.jcall(j2r, "S", "getValueString", check = FALSE))
  } else if (result[3] == EC_WARNING_MISSING_LOGICAL_VALUES && warn.missing.logical) {
    warning(MSG_WARNING_MISSING_LOGICAL_VALUES, call. = FALSE)
  } else if (result[3] == EC_WARNING_MISSING_RAW_VALUES && warn.missing.raw) {
    warning(MSG_WARNING_MISSING_RAW_VALUES, call. = FALSE)
  } else if (result[1] == TC_UNSUPPORTED) {
    # This should never happen. The JavaToR class should raise this error on the Java side.
    # If this error is thrown it indicates that a developer has broken something...
    stop("The Java data type could not be converted to an R object. This exception is unexpected at this location. Please report this error as a bug with relevant code.")
  }
  return(result)
}

