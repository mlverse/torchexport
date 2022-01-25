#' Generates code that exports code from C++ extensions
#'
#' This function is used by the CmakeList.txt file template to autogenerate
#' headers and declarations for exported functions in torch C++ extensions.
#'
#' @inheritParams pkgload::load_all
#'
#' @export
export <- function(path = pkg_path()) {
  withr::with_dir(path, {
    decls <- get_declarations()

    if (nrow(decls) == 0)
      return(invisible(NULL))
    parseds <- lapply(decls$context, decor::parse_cpp_function)
    decls <- lapply(parseds, generate_decls)
    decls <- purrr::transpose(decls)

    export_cpp <- exports_cpp(decls$error_handled)
    export_h <- exports_h(decls$empty_decl, decls$wrapper)


    replace_defs(parseds)
    readr::write_lines(export_cpp, "csrc/src/exports.cpp")
    readr::write_lines(export_h, fs::path("csrc/include/", tolower(get_package_name()), "exports.h"))
  })

  invisible(NULL)
}

pkg_path <- pkgload::pkg_path


generate_decls <- function(parsed) {
  list(
    error_handled = make_error_handled(parsed),
    wrapper = make_wrapper(parsed),
    empty_decl = make_empty_declaration(parsed)
  )
}


make_error_handled <- function(parsed) {
  glue_code("
<<make_declaration(parsed, macro = '', prefix = '')>>;
<<make_declaration(parsed, type = 'c_style')>> {
  try {
    <<make_return(parsed)>> <<make_raw(parsed)>>(<<parsed$name>>(<<make_call(parsed, type = 'lantern')>>));
  } <<get_package_name()>>_HANDLE_EXCEPTION
  <<if (make_ret_type(parsed, 'c_style') != 'void') paste('return (',make_ret_type(parsed, 'c_style'),') NULL')>>;
}
")
}

make_wrapper <- function(parsed) {
  glue_code("
<<make_declaration(parsed, macro = '', prefix = '', inline = TRUE)>> {
  <<if (parsed$return_type != 'void') 'auto ret = ' else ''>> _<<parsed$name>>(<<make_call(parsed)>>);
  host_exception_handler();
  <<if (parsed$return_type != 'void') 'return ret;' else ''>>
}
")
}

make_empty_declaration <- function(parsed) {
  glue_code("<<make_declaration(parsed)>>;")
}


glue_code <- function(..., .envir = parent.frame()) {
  glue::glue(..., .open = "<<", .close = ">>", .envir = .envir)
}

make_declaration <- function(parsed, prefix = "_", macro = NULL, inline = FALSE,
                             type = c("unchanged", "c_style", "rcpp")) {
  type <- match.arg(type)
  if (is.null(macro)) {
    macro <- glue_code("<<get_package_name()>>_API ")
  } else {
    macro <- macro
  }
  inline <- ifelse(inline, "inline ", "")
  glue_code("<<macro>><<inline>><<make_ret_type(parsed, type = type)>> <<prefix>><<parsed$name>> (<<make_signature(parsed, type = type)>>)")
}

make_signature <- function(parsed, type = c("unchanged", "c_style", "rcpp")) {
  type <- match.arg(type)
  args <- parsed$args[[1]]
  types <- args$type
  if (type == "c_style") {
    types <- make_c_types(types)
  }
  args <- paste(types, args$name)
  paste(args, collapse = ", ")
}

make_ret_type <- function(parsed, type = c("unchanged", "c_style", "rcpp")) {
  type <- match.arg(type)
  if (type == "c_style")
    make_c_types(parsed$return_type)
  else
    parsed$return_type
}

make_c_types <- function(types) {
  types <- ifelse(types == "torch::Tensor", "void*", types)
  types <- ifelse(types == "std::vector<torch::Tensor>", "void*", types)
  types
}

make_lantern_type <- function(types) {
  types <- ifelse(types == "torch::Tensor", "Tensor", types)
  types <- ifelse(types == "std::vector<torch::Tensor>", "TensorList", types)
  types
}

lantern_supported_types <- function() {
  c("torch::Tensor", "std::vector<torch::Tensor>")
}

make_rcpp_type <- function(types) {
  types <- ifelse(types == "torch::Tensor", "torch::Tensor", types)
  types <- ifelse(types == "std::vector<torch::Tensor>", "torch::TensorList", types)
  types
}

make_call <- function(parsed, type = c("unchanged", "lantern", "rcpp")) {
  type <- match.arg(type)
  args <- parsed$args[[1]]
  names <- args$name
  types <- args$type
  if (type == "lantern") {
    # we can only add from_raw when the type is supported
    names <- ifelse(types %in% lantern_supported_types(),
                    paste0("from_raw::", make_lantern_type(types), "(", names, ")"),
                    names)
  }
  paste(names, collapse = ", ")
}

make_return <- function(parsed) {
  if (parsed$return_type == "void")
    ""
  else
    "return "
}

make_raw <- function(parsed) {
  if (parsed$return_type %in% c("torch::Tensor", "std::vector<torch::Tensor>")) {
    paste0("make_raw::", make_lantern_type(parsed$return_type))
  } else {
    ""
  }
}