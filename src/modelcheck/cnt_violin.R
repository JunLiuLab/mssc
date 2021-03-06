options(error = traceback)
options(warn = 0)
library(optparse)
suppressPackageStartupMessages(library(tidyverse))
library(Seurat)
import::from(here, here)
import::from(stringr, str_glue)
suppressPackageStartupMessages(library(ggpubr))

options("import.path" = here("rutils"))
myt <- modules::import("transform")
myfit <- modules::import("myfitdistr")
# modules::reload(myfit)


datadir <- here("data")
figdir <- here("src", "modelcheck", "figures")
pbmc_IL8_dirnm <- "antiPDL1_PBMC_IL8"

myaxis_text_x <- ggplot2::element_text(size = 12, angle = 45)
myaxis_title_x <- ggplot2::element_blank()
myaxis_text_y <- ggplot2::element_text(size = 14, face = "bold")
myaxis_title_y <- ggplot2::element_text(size = 16, face = "bold")
mytitle <- ggplot2::element_text(size = 15, hjust = 0.5)

## * functions
is_outlier <- function(x, up_prob = 0.995) {
  return(x > 5 * quantile(x, up_prob))
}

singleviolin <- function(whichdf, whichgene, whichgroup,
                         axis_text_x = myaxis_text_x,
                         axis_text_y = myaxis_text_y,
                         axis_title = mytitle,
                         axis_title_x = myaxis_title_x,
                         axis_title_y = myaxis_title_y,
                         legend_position = "none") {
  ggplot(whichdf, aes_string(x = whichgroup,
    y = whichgene, fill = whichgroup)) +
    geom_violin(scale = "width", adjust = 1, trim = TRUE) +
    geom_jitter(shape = 16, height = 0) +
    stat_summary(fun.data = "mean_sdl", mult = 1,
      geom = "pointrange", color = "red",
      size = 0.2) +
    theme(plot.title = axis_title,
      legend.position = legend_position,
      axis.text.x = axis_text_x,
      axis.text.y = axis_text_y,
      axis.title.x = axis_title_x,
      axis.title.y = axis_title_y)
}

groupviolin <- function(gbcmatrix, genes, groups, limitcells = NULL,
                        rm_outliers = T) {
  if (is.null(limitcells)) {
    plotdata <- as.data.frame(t(gbcmatrix[genes, ]))
    mygroups <- groups
  } else {
    plotdata <- as.data.frame(t(gbcmatrix[genes, limitcells]))
    mygroups <- groups[limitcells]
  }
  colnames(plotdata) <- genes
  plotdata$pop <- mygroups
  lapply(seq_len(length(genes)), FUN = function(i) {
    tmp <- plotdata[c(genes[i], "pop")]
    if (rm_outliers) {
      myoutliers <- is_outlier(tmp[, genes[i]])

      nout <- length(which(myoutliers == T))
      message(str_glue("remove {nout} outliers"))
      myq <- 0.999
      myqv <- quantile(tmp[, 1], myq)
      myoutv <- tmp[myoutliers, 1]
      message(str_glue("{myq} quantile is: {myqv}"))
      message(str_glue("outlier values: {myoutv}"))

      tmp <- plotdata[!myoutliers, ]
    }
    singleviolin(tmp, genes[i], "pop")
  })
}

compareviolin_cnt_tpm <- function(cnt, scaledata,
                                  genes, groups,
                                  limitcells = NULL,
                                  title = ggpubr::text_grob("Hi", size = 18),
                                  savedir = figdir,
                                  fnm = "Hi",
                                  mydpi = 100,
                                  myheight = 7,
                                  mywidth = 14,
                                  rm_outliers = T) {
  cntplt <- groupviolin(cnt, genes, groups, limitcells)
  sclplt <- groupviolin(scaledata, genes, groups, limitcells)
  p1 <- ggpubr::ggarrange(plotlist = cntplt, nrow = 1)
  p2 <- ggpubr::ggarrange(plotlist = sclplt, nrow = 1)
  p <- ggpubr::ggarrange(plotlist = list(p1, p2), nrow = 2) %>%
    ggpubr::annotate_figure(p = ., top = title)
  ggplot2::ggsave(plot = p, filename = paste(savedir, fnm, sep = "/"),
    dpi = mydpi, width = mywidth, height = myheight)
  return(p)
}

## load seurat data
pbmcseurat <- readRDS(paste(datadir, pbmc_IL8_dirnm, "seurat.RDS", sep = "/"))
pbmccnt <- as.matrix(pbmcseurat@assays$RNA@counts)
pbmctpm <- as.matrix(pbmcseurat@assays$RNA@data)
pbmcinds <- pbmcseurat@meta.data$patient
pbmc_cellanno <- pbmcseurat@meta.data$seurat_clusters

## cytototic T cells
mycluster <- 2
ind <- "R1"

## 314 cells
oneindcells <- (pbmc_cellanno == mycluster) & (grepl(ind, colnames(pbmccnt)))
## 3885 cells
mulindcells <- pbmc_cellanno == mycluster

DEGs <- c("CCL4L1", "CCL4L2", "CCL3L1", "CCL3L3")
heavyzeroGs <- c("MIR155HG", "TNFRSF4", "ICAM1", "NA.499", "HIST2H2AA4")
heavyindeffectGs <- c("HBB", "HBA2", "HBA1")

## violin plot
violin_all_cells_title <- ggpubr::text_grob(
  "Violin Plot Compare: Count vs TPM on all the cells",
  size = 18, color = "darkred", face = "bold")

cnt_vs_scale_degs_all <- compareviolin_cnt_tpm(
  pbmccnt, pbmctpm, DEGs, pbmcinds, limitcells = NULL,
  title = violin_all_cells_title,
  fnm = "vln_cnt-tpm_DEGs_allcells.png")

cnt_vs_scale_heavyzeros_all <- compareviolin_cnt_tpm(
  pbmccnt, pbmctpm, heavyzeroGs, pbmcinds, limitcells = NULL,
  title = violin_all_cells_title,
  fnm = "vln_cnt-tpm_heavyzeros_allcells.png")

cnt_vs_scale_heavyindeff_all <- compareviolin_cnt_tpm(
  pbmccnt, pbmctpm, heavyindeffectGs, pbmcinds, limitcells = NULL,
  title = violin_all_cells_title,
  fnm = "vln_cnt-tpm_heavyindeff_allcells.png")

violin_cytoTcell_title <- ggpubr::text_grob(
  "Violin Plot Compare: Count vs TPM on cytotoxic T cells",
  size = 18, color = "darkred", face = "bold")
cnt_vs_scale_degs_cytoTcell <- compareviolin_cnt_tpm(
  pbmccnt, pbmctpm, DEGs, pbmcinds, limitcells = mulindcells,
  title = violin_cytoTcell_title,
  fnm = "vln_cnt-tpm_DEGs_cytotoxicTcell.png")
cnt_vs_scale_heavyzeros_cytoTcell <- compareviolin_cnt_tpm(
  pbmccnt, pbmctpm, heavyzeroGs, pbmcinds, limitcells = mulindcells,
  title = violin_cytoTcell_title,
  fnm = "vln_cnt-tpm_heavyzeros_cytotoxicTcell.png"
)
cnt_vs_scale_heavyindeff_cytoTcell <- compareviolin_cnt_tpm(
  pbmccnt, pbmctpm, heavyindeffectGs, pbmcinds, limitcells = mulindcells,
  title = violin_cytoTcell_title,
  fnm = "vln_cnt-tpm_heavyindeff_cytotoxicTcell.png")
