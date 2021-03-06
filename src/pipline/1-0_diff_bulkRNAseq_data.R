options(error = traceback)
suppressPackageStartupMessages(library(TCGAbiolinks))
suppressPackageStartupMessages(library(org.Hs.eg.db))
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(here))
suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(import::from(limma, contrasts.fit))

## * load util functions.
options("import.path" = here("rutils"))
myt <- modules::import("transform")
mytcga <- modules::import("tcga")

## * configs
cancer_project <- "TCGA-UVM"
data_dir <- "data"
subdir <- "UM"

genes_fnm <- "tcga_bulk_gsymbol.rds"
gene_filter_method <- "quantile"
gene_qnt_cut_meanreads <- 0.1

de_pipeline <- "edgeR"
de_method <- "glmLRT"
de_fdr_init_cut <- 0.7
de_fdr_cut <- 0.1
de_logfc_init_cut <- 0.1
de_logfc_cut <- 1
de_outfnm <- "tcga_diffexp_genes.rds"
enrichde_outfnm <- "tcga_goenrich_diffexp_genes.rds"
fpde_outfnm <- "tcga_fp_diffexp_genes.rds"
tnde_outfnm <- "tcga_tn_diffexp_genes.rds"

message("bulkRNAseq configs: ")
args <- list(
    de_pipeline = de_pipeline, de_method = de_method,
    de_fdr_cut = de_fdr_cut, de_logfc_cut = de_logfc_cut,
    de_outfnm = de_outfnm,
    cancer = cancer_project, genes_fnm = genes_fnm,
    gene_filter_method = gene_filter_method,
    gene_qnt_cut_meanreads = gene_qnt_cut_meanreads
)
message(str(args))

query <- TCGAbiolinks::GDCquery(
    project = cancer_project,
    data.category = "Transcriptome Profiling",
    data.type = "Gene Expression Quantification",
    workflow.type = "HTSeq - Counts"
)
sample_barcodes <- TCGAbiolinks::getResults(query, cols = c("cases"))

## same as sample_barcodes
data_tp <- TCGAbiolinks::TCGAquery_SampleTypes(
    barcode = sample_barcodes,
    typesample = "TP"
)

## below is empty
## data_nt <- TCGAbiolinks::TCGAquery_SampleTypes(
## barcode = sample_barcodes,
## typesample = "NT"
## )

## * download data
GDCdownload(query = query, directory = here(data_dir, subdir, "GDCdata"))

data_prep <- TCGAbiolinks::GDCprepare(
    query = query,
    save = T, save.filename = "TCGA_HTSeq_Countds.rds",
    directory = here(data_dir, subdir, "GDCdata")
)
## * save data
saveRDS(data_prep, here(data_dir, subdir, "tcga_GDCprepare.rds"))
## reload data: data_prep <- readRDS(here(data_dir, subdir, "tcga_GDCprepare.rds"))
data_prep <- TCGAbiolinks::TCGAanalyze_Preprocessing(
    object = data_prep,
    cor.cut = 0.6
)
data_norm <- TCGAbiolinks::TCGAanalyze_Normalization(
    tabDF = data_prep,
    geneInfo = TCGAbiolinks::geneInfoHT,
    method = "geneLength"
)

## ** mapping ensemble to symbol
message("Raw bulkRNAseq: ")
myt$print_sc(nrow(data_norm), ncol(data_norm),
    row = "gene", plat = "bulkRNAseq"
)

ensembl2symbol_bulk <- AnnotationDbi::select(org.Hs.eg.db,
    keys = rownames(data_norm),
    column = "SYMBOL",
    keytype = "ENSEMBL"
)
message("Draft remove duplicated ENSEMBLs ... ")
ensembl2symbol_bulk <- ensembl2symbol_bulk[
    !duplicated(ensembl2symbol_bulk$ENSEMBL),
]
kept_rows <- which(!is.na(ensembl2symbol_bulk$SYMBOL))
data_norm <- data_norm[kept_rows, ]
rownames(data_norm) <- ensembl2symbol_bulk[kept_rows, "SYMBOL"]

message("After mapping to SYMBOL: ")
myt$print_sc(nrow(data_norm), ncol(data_norm),
    row = "gene", plat = "bulkRNAseq"
)

## ** remove MT genes
data_norm <- myt$rm_mt(data_norm)

## ** remove low-reads genes
data_fit <- TCGAbiolinks::TCGAanalyze_Filtering(
    tabDF = data_norm,
    method = gene_filter_method,
    qnt.cut = gene_qnt_cut_meanreads
)

## ** save considered genes.
saveRDS(object = rownames(data_norm), file = here(
    data_dir, subdir,
    genes_fnm
))

## * load meta data
## TODO: use library of SummarizedExperiment
## colData to get the sample information
meta_data <- data.table::fread(here(
    data_dir, "tcga_patient",
    "clinical_PANCAN_patient_with_followup.tsv"
))

simple_barcodes <- substring(colnames(data_fit), 1, 12)
the_meta_data <- meta_data[
    match(simple_barcodes, bcr_patient_barcode),
    "gender"
]
message(stringr::str_glue("{cancer_project} patient genders: "))
table(the_meta_data)

dea <- TCGAbiolinks::TCGAanalyze_DEA(
    mat1 = data_fit[, which(the_meta_data == "FEMALE")],
    mat2 = data_fit[, which(the_meta_data == "MALE")],
    pipeline = de_pipeline,
    Cond1type = "FEMALE",
    Cond2type = "MALE",
    fdr.cut = de_fdr_init_cut,
    logFC.cut = de_logfc_init_cut,
    method = de_method
)
dea <- dea[order(dea$PValue), ]
dea$genesymbol <- rownames(dea)
message(
    stringr::str_glue(
        "init fdr({de_fdr_init_cut}) ",
        " logfc({de_logfc_init_cut}): ",
        "num of genes({nrow(dea)})"
    )
)

degs <- dea[(abs(dea$logFC) > de_logfc_cut) & (dea$FDR < de_fdr_cut), ]

message(
    stringr::str_glue(
        "fdr({de_fdr_cut}) and logfc({de_logfc_cut}): ",
        "num of genes({nrow(degs)})"
    )
)

## * GO enrichment analysis
GOcommongenes <- mytcga$TCGAanalyze_EAcomplete(
    TFname = "DEA genes",
    RegulonList = rownames(degs)
)
enrichdegs <- list(genesymbol = unique(unlist(GOcommongenes)))
message(
  stringr::str_glue("GO enriched de genes: {length(enrichdegs$genesymbol)}"))
## ansEA <- TCGAbiolinks::TCGAanalyze_EAcomplete(
##     TFname = "DEA genes in UVM sex-related",
##     RegulonList = rownames(degs)
## )

## TCGAbiolinks::TCGAvisualize_EAbarplot(
##     tf = rownames(ansEA$ResBP),
##     GOBPTab = ansEA$ResBP,
##     GOCCTab = ansEA$ResCC,
##     GOMFTab = ansEA$ResMF,
##     PathTab = ansEA$ResPat,
##     nRGTab = rownames(degs),
##     nBar = 20
## )

## * saee results
saveRDS(
    object = degs, file =
        here(data_dir, subdir, de_outfnm)
)

saveRDS(object = enrichdegs, file = here(data_dir,
                                         subdir, enrichde_outfnm))

nondegs <- dea[dea$FDR > de_fdr_cut, ]
nondegs <- nondegs[order(nondegs$PValue), ]

fp_degs <- nondegs[seq_len(2 * nrow(degs)), ]

tn_from <- nrow(degs) + 100
tn_to <- tn_from + 2 * nrow(degs)
tn_degs <- nondegs[seq(tn_from, tn_to), ]

saveRDS(
    object = fp_degs, file =
        here(data_dir, subdir, fpde_outfnm)
)

saveRDS(
    object = tn_degs, file =
        here(data_dir, subdir, tnde_outfnm)
)
