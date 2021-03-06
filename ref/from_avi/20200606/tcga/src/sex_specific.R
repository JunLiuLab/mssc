library(data.table)
library(magri)
library(TCGAbiolinks)
CancerProject <- "TCGA-HNSC"
DataDirectory <- paste0("../GDC/", gsub("-", "_", CancerProject))
FileNameData <- paste0(DataDirectory, "_", "HTSeq_Counts", ".rda")

query <- GDCquery(
  project = CancerProject,
  data.category = "Transcriptome Profiling",
  data.type = "Gene Expression Quantification",
  workflow.type = "HTSeq - Counts"
)

samplesDown <- getResults(query, cols = c("cases"))

dataSmTP <- TCGAquery_SampleTypes(
  barcode = samplesDown,
  typesample = "TP"
)

dataSmNT <- TCGAquery_SampleTypes(
  barcode = samplesDown,
  typesample = "NT"
)
# dataSmTP_short <- dataSmTP[1:10]
# dataSmNT_short <- dataSmNT[1:10]

queryDown <- GDCquery(
  project = CancerProject,
  data.category = "Transcriptome Profiling",
  data.type = "Gene Expression Quantification",
  workflow.type = "HTSeq - Counts",
  barcode = c(dataSmTP)
)

GDCdownload(query = queryDown)

dataPrep1 <- GDCprepare(
  query = queryDown,
  save = TRUE,
  save.filename = "TCGA_HNSC_HTSeq_Countds.rda"
)
dataPrep <- TCGAanalyze_Preprocessing(
  object = dataPrep1,
  cor.cut = 0.6,
  datatype = "HTSeq - Counts"
)

dataNorm <- TCGAanalyze_Normalization(
  tabDF = dataPrep,
  geneInfo = geneInfoHT,
  method = "gcContent"
)
dataNorm <- TCGAanalyze_Normalization(
  tabDF = dataPrep,
  geneInfo = geneInfoHT,
  method = "geneLength"
)
dataFilt <- TCGAanalyze_Filtering(
  tabDF = dataNorm,
  method = "quantile",
  qnt.cut = 0.25
)

### dataframe will have genes from dataFilt but raw counts from dataPrep
# dataPrep_raw <- UseRaw_afterFilter(dataPrep, dataFilt)

### Read the meta data regarding sex info downloaded from  https://gdc.cancer.gov/about-data/publications/pancanatlas
meta.data <- fread("~/liulab_home/data/tcga/TCGA_gdc/clinical_PANCAN_patient_with_followup.tsv")
barcode.curr <- substring(colnames(dataFilt), 1, 12)
meta.dat.matched <- meta.data[match(barcode.curr, bcr_patient_barcode)]
female.inx <- which(meta.dat.matched$gender == "FEMALE")
male.inx <- which(meta.dat.matched$gender == "MALE")
dataDEGs <- TCGAanalyze_DEA(
  mat1 = dataFilt[, female.inx],
  mat2 = dataFilt[, male.inx],
  pipeline = "limma",
  Cond1type = "FEMALE",
  Cond2type = "MALE",
  fdr.cut = 0.01,
  logFC.cut = 1,
  method = "glmLRT", ClinicalDF = data.frame()
)

library(clusterProfiler)

gene.df <- clusterProfiler::bitr(rownames(dataDEGs),
  fromType = "ENSEMBL",
  toType = "SYMBOL",
  OrgDb = org.Hs.eg.db
)
dataDEGs$symbol <- gene.df[match(rownames(dataDEGs), gene.df$ENSEMBL), ]$SYMBOL
saveRDS(file = "tcga.skcm.sex.deg.RDS", dataDEGs)

TCGAanalyze_Preprocessing <- function(object, cor.cut = 0, filename = NULL, width = 1000,
                                      height = 1000, datatype = names(assays(object))[1]) {
  if (grepl("raw_count", datatype) & any(grepl(
    "raw_count",
    names(assays(object))
  ))) {
    datatype <- names(assays(object))[grepl(
      "raw_count",
      names(assays(object))
    )]
  }
  if (!any(grepl(datatype, names(assays(object))))) {
    stop(paste0(
      datatype, " not found in the assay list: ",
      paste(names(assays(object)), collapse = ", "), "\n  Please set the correct datatype argument."
    ))
  }
  if (!(is.null(dev.list()["RStudioGD"]))) {
    dev.off()
  }
  if (is.null(filename)) {
    filename <- "PreprocessingOutput.png"
  }
  pdf(filename, width = width, height = height)
  par(oma = c(10, 10, 10, 10))
  ArrayIndex <- as.character(1:length(colData(object)$barcode))
  pmat_new <- matrix(0, length(ArrayIndex), 4)
  colnames(pmat_new) <- c(
    "Disease", "platform", "SampleID",
    "Study"
  )
  rownames(pmat_new) <- as.character(colData(object)$barcode)
  pmat_new <- as.data.frame(pmat_new)
  pmat_new$Disease <- as.character(colData(object)$definition)
  pmat_new$platform <- "platform"
  pmat_new$SampleID <- as.character(colData(object)$barcode)
  pmat_new$Study <- "study"
  tabGroupCol <- cbind(pmat_new, Color = matrix(
    0, nrow(pmat_new),
    1
  ))
  for (i in seq_along(unique(tabGroupCol$Disease))) {
    tabGroupCol[
      which(tabGroupCol$Disease == tabGroupCol$Disease[i]),
      "Color"
    ] <- rainbow(length(unique(tabGroupCol$Disease)))[i]
  }
  pmat <- pmat_new
  phenodepth <- min(ncol(pmat), 3)
  order <- switch(phenodepth + 1, ArrayIndex, order(pmat[
    ,
    1
  ]), order(pmat[, 1], pmat[, 2]), order(pmat[, 1], pmat[
    ,
    2
  ], pmat[, 3]))
  arraypos <- (1:length(ArrayIndex)) * (1 / (length(ArrayIndex) -
    1)) - (1 / (length(ArrayIndex) - 1))
  arraypos2 <- seq(1:length(ArrayIndex) - 1)
  for (i in 2:length(ArrayIndex)) {
    arraypos2[i - 1] <- (arraypos[i] + arraypos[i - 1]) / 2
  }
  layout(matrix(c(
    1, 1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 2, 3, 3,
    3, 4
  ), 4, 4, byrow = TRUE))
  c <- cor(assay(object, datatype)[, order], method = "spearman")
  image(c, xaxt = "n", yaxt = "n", main = "Array-Array Intensity Correlation after RMA")
  for (i in 1:length(names(table(tabGroupCol$Color)))) {
    currentCol <- names(table(tabGroupCol$Color))[i]
    pos.col <- arraypos[which(tabGroupCol$Color == currentCol)]
    lab.col <- colnames(c)[which(tabGroupCol$Color == currentCol)]
    axis(2,
      labels = lab.col, at = pos.col, col = currentCol,
      lwd = 6, las = 2
    )
  }
  m <- matrix(pretty(c, 10), nrow = 1, ncol = length(pretty(
    c,
    10
  )))
  image(m, xaxt = "n", yaxt = "n", ylab = "Correlation Coefficient")
  axis(2, labels = as.list(pretty(c, 10)), at = seq(0, 1, by = (1 / (length(pretty(
    c,
    10
  )) - 1))))
  abline(h = seq((1 / (length(pretty(c, 10)) - 1)) / 2, 1 - (1 / (length(pretty(
    c,
    10
  )) - 1)), by = (1 / (length(pretty(c, 10)) - 1))))
  box()
  boxplot(c,
    outline = FALSE, las = 2, lwd = 6, col = tabGroupCol$Color,
    main = "Boxplot of correlation samples by samples after normalization"
  )
  dev.off()
  samplesCor <- rowMeans(c)
  objectWO <- assay(object, datatype)[, samplesCor > cor.cut]
  colnames(objectWO) <- colnames(object)[samplesCor > cor.cut]
  return(objectWO)
}
